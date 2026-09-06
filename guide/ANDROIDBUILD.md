# AndroidBuild local integration

Waddle Forever is managed as an AndroidBuild **custom desktop project**. Android/APK/ADB gates do not apply to this repository.

## Canonical local checkout

`V:\AndroidBuild\Repositories\TEST-Waddle-Forever`

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

For compatibility with the historical project scripts, root `node_modules`, `compiled`, and `dist` are NTFS junctions into `.work`. Existing tracked `media` is intentionally not relocated in this phase because timeline and SWF paths must remain byte/path compatible until the future content-resolver migration is validated.

The player database in `data` is also not relocated automatically; save-state migration requires an explicit persistence design rather than treating user data as disposable build output.

## Toolchain

Reference build toolchain:

- Node.js 20.12.2
- Yarn Classic 1.22.22
- npm 9.8.1 is recorded as the historical reference but is informational because dependency installation is performed by Yarn.
- FFDec/JPEXS 26.2.1 is provisioned by AndroidBuild Core under `V:\AndroidBuild\Tools\FFDec\26.2.1` and is not vendored into this repository.

`.env` is generated from `template.env` when missing and remains untracked.

## Bootstrap

From the canonical repository in an interactive Windows session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github\scripts\waddle-bootstrap.ps1
```

The bootstrap imports `Core\Current`, initializes `.work`, creates compatibility junctions, creates `.env` when necessary, validates the pinned Node/Yarn toolchain, and resolves the global FFDec tool.

## Core build

The authoritative build path is the AndroidBuild `repo-hooks` adapter. The build hook performs:

1. `yarn install --frozen-lockfile`
2. `yarn build-packages`
3. `yarn build-tsc`
4. `yarn lint`

Build logs and summaries are stored under `.work`; Core separately records build provenance and exact source SHA.

The workflow `Waddle AndroidBuild Local Integration` synchronizes the workflow SHA into the canonical repository through `Sync-AndroidBuildRepositoryExactHead`, runs the project precheck and build through Core, and verifies that the heavy directories are physically rooted in `.work`.
