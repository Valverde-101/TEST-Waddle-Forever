'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

async function main() {
  const repo = path.resolve(__dirname, '..');
  const compiledStorage = path.join(repo, 'compiled', 'server', 'database', 'storage-layout.js');
  if (!fs.existsSync(compiledStorage)) {
    throw new Error(`compiled storage module missing: ${compiledStorage}`);
  }

  // The production app runs with the repository as cwd. Reproduce that exact
  // contract so compiled/common/version.js resolves the canonical package.json
  // instead of looking at the GitHub runner checkout directory.
  process.chdir(repo);

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'waddle-storage-probe-'));
  const portableRoot = path.join(root, 'user-data');
  const legacyData = path.join(root, 'data');
  const legacyPenguins = path.join(legacyData, 'penguins');
  const portablePenguins = path.join(portableRoot, 'data', 'penguins');

  try {
    fs.mkdirSync(legacyPenguins, { recursive: true });
    fs.writeFileSync(path.join(legacyData, '.version'), '1.5.1', 'utf8');
    fs.writeFileSync(path.join(legacyPenguins, 'seq'), '101', 'utf8');
    fs.writeFileSync(path.join(legacyPenguins, '101.json'), JSON.stringify({
      name: 'StorageProbe',
      coins: 500,
      inventory: [1],
      furniture: {},
      is_member: true
    }), 'utf8');

    process.env.WADDLE_USER_DATA_DIR = portableRoot;
    process.env.WADDLE_PORTABLE = '1';

    delete require.cache[require.resolve(compiledStorage)];
    const storage = require(compiledStorage);

    const prepared = storage.preparePortablePenguinStorage();
    const migratedProfile = path.join(prepared.penguinsRoot, '101.json');
    if (!fs.existsSync(migratedProfile)) {
      throw new Error(`legacy profile was not migrated: ${migratedProfile}`);
    }

    const migrated = JSON.parse(fs.readFileSync(migratedProfile, 'utf8'));
    if (migrated.name !== 'StorageProbe') {
      throw new Error(`migrated profile mismatch: ${JSON.stringify(migrated)}`);
    }

    // Reproduce the exact production failure: the parent exists, but the
    // penguins directory disappears before a scandir/readdir operation.
    fs.rmSync(portablePenguins, { recursive: true, force: true });
    if (fs.existsSync(portablePenguins)) {
      throw new Error(`probe could not remove penguins directory: ${portablePenguins}`);
    }

    const names = await storage.withPenguinStorageRecovery('certification.scandir', async () => {
      return fs.promises.readdir(portablePenguins);
    });

    if (!Array.isArray(names)) {
      throw new Error('recovered scandir did not return an array');
    }
    if (!fs.existsSync(portablePenguins)) {
      throw new Error(`storage recovery did not recreate: ${portablePenguins}`);
    }
    if (!names.includes('101.json')) {
      throw new Error(`storage recovery recreated the directory but lost the legacy profile: ${names.join(',')}`);
    }

    const restored = JSON.parse(fs.readFileSync(path.join(portablePenguins, '101.json'), 'utf8'));
    if (restored.name !== 'StorageProbe') {
      throw new Error(`restored profile mismatch: ${JSON.stringify(restored)}`);
    }

    // The recovery path should be usable immediately for a new atomic write.
    const temporary = path.join(portablePenguins, '.102.probe.tmp');
    const destination = path.join(portablePenguins, '102.json');
    await fs.promises.writeFile(temporary, JSON.stringify({ name: 'RecoveredProbe' }), 'utf8');
    await fs.promises.rename(temporary, destination);
    if (!fs.existsSync(destination)) {
      throw new Error(`post-recovery write failed: ${destination}`);
    }

    process.stdout.write(
      `WADDLE_STORAGE_RECOVERY_PROBE=PASS legacy_migration=true missing_directory_recovery=true profile_restoration=true atomic_write=true root=${root}\n`
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch(error => {
  console.error(`WADDLE_STORAGE_RECOVERY_PROBE=FAIL ${error && error.stack ? error.stack : error}`);
  process.exitCode = 1;
});
