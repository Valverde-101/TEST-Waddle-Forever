import fs from 'fs';
import path from 'path';

type PackageMetadata = {
  version?: unknown;
};

const packageCandidates = [
  // Normal source/packaged layout: compiled/common -> application root.
  path.resolve(__dirname, '..', '..', 'package.json'),
  // AndroidBuild external runtime deliberately keeps the repository as cwd so
  // settings/media/source-owned metadata remain canonical outside Runtime/.
  path.resolve(process.cwd(), 'package.json')
];

let packageMetadata: PackageMetadata | undefined;
let resolvedPackagePath: string | undefined;

for (const candidate of packageCandidates) {
  if (!fs.existsSync(candidate)) {
    continue;
  }

  try {
    packageMetadata = JSON.parse(fs.readFileSync(candidate, 'utf8')) as PackageMetadata;
    resolvedPackagePath = candidate;
    break;
  } catch (error) {
    const detail = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
    throw new Error(`WADDLE_PACKAGE_METADATA=FAIL path=${candidate} error=${detail}`);
  }
}

if (!packageMetadata || typeof packageMetadata.version !== 'string' || packageMetadata.version.length === 0) {
  throw new Error(`WADDLE_PACKAGE_METADATA=FAIL reason=version_unresolved candidates=${packageCandidates.join(';')}`);
}

export const PACKAGE_METADATA_PATH = resolvedPackagePath as string;
export const VERSION = packageMetadata.version;
