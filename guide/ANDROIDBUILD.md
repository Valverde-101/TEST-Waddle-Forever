# AndroidBuild local integration

Waddle Forever is managed as an AndroidBuild **custom desktop project**. Android/APK/ADB gates do not apply to this repository.

## Canonical local checkout

Current installation path on PC-WILLTHOM:

`V:\AndroidBuild\Repositories\TEST-Waddle-Forever`

The adapter does not hardcode `V:`. It resolves `ANDROIDBUILD_ROOT` from the supplied Core context/environment, then from the canonical `Repositories/<repo>` layout, and finally by scanning ready local drives for `AndroidBuild\Core\Current`.

The repository source remains Git-owned. Heavy mutable state lives under `.work` and is preserved by AndroidBuild exact-head synchronization.

## Heavy workspace

Core creates the standard `.work` layout. Waddle adds these project pools:

- `.work\dependencies\node_modules`
- `.work\cache\yarn`
- `.work\build\compiled`
- `.work\dist\package`
- `.work\runtime`
- `.work\downloads`
- `.work\content`
- `.work\swf-analysis`
- `.work\diagnostics`
- `.work\logs`

For compatibility with the historical project scripts, root `node_modules`, `compiled`, and `dist` are NTFS junctions into `.work`.

`.work` is validated through `git check-ignore`, not by matching one literal line in `.gitignore`. The precheck also rejects any tracked file below `.work`, so the invariant being tested is the actual Git behavior rather than a fragile text pattern.

Existing tracked `media` is intentionally not relocated in this phase because timeline and SWF paths must remain byte/path compatible until the future content-resolver migration is validated. The first shallow materialization can therefore still be large; subsequent exact-SHA syncs reuse the local Git object store.

The player database in `data` is also not relocated automatically; save-state migration requires an explicit persistence design rather than treating user data as disposable build output.

## Core and toolchain contract

Minimum AndroidBuild Core: **3.0.14**.

Reference build toolchain:

- Node.js 20.12.2
- Yarn Classic 1.22.22
- npm 9.8.1 is retained only as the historical reference; dependency installation is performed by Yarn.
- FFDec/JPEXS 26.2.1 is provisioned globally by AndroidBuild Core and is not vendored into this repository.

The minimum Core version is defined once in `.androidbuild.json`; the Waddle adapter reads that value instead of carrying another hardcoded version constant.

`.env` is generated from `template.env` when missing and remains untracked.

## Bootstrap

From the canonical repository in an interactive Windows session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\waddle-bootstrap.ps1
```

The bootstrap imports `Core\Current`, initializes `.work`, creates compatibility junctions, creates `.env` when necessary, validates the pinned Node/Yarn toolchain, and resolves the global FFDec tool.

## Core build

The authoritative build path is the AndroidBuild `repo-hooks` adapter. The build hook performs:

1. `yarn install --frozen-lockfile --non-interactive`
2. `yarn build-packages`
3. reset the real `.work\build\compiled` target while preserving/recreating the root junction
4. `yarn exec tsc`
5. `yarn exec tsc-alias`
6. `yarn build-browser`
7. `yarn copy-files`
8. `yarn lint`

The explicit TypeScript sequence is intentional: upstream `yarn build-tsc` begins by removing `compiled`, which would delete the compatibility junction itself.

Build logs and summaries are stored under `.work`; Core separately records build provenance and exact source SHA.

## Local integration workflow

`Waddle AndroidBuild Local Integration` uses the current `actions/setup-node` v7 action runtime while still installing the project toolchain Node 20.12.2.

The workflow:

1. resolves Core 3.0.14+
2. synchronizes the exact PR SHA into the canonical repository with `FetchDepth=1`
3. initializes and validates `.work`
4. runs the project precheck through Core
5. runs the build through Core
6. verifies exact HEAD, workspace/provenance files, and NTFS junction invariants

Android, APK-FINAL, APK-APROVE-ADB and physical ADB remain explicitly `NOT_APPLICABLE` for Waddle Forever.
