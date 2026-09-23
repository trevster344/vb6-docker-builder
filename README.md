# vb6-builder

A project-agnostic Visual Basic 6 build image. Point it at any VB6 project and
it compiles it under Wine — no Windows machine required.

Visual Studio 6 / VB6 Enterprise + Service Pack 6 are installed into a Wine
prefix **at image-build time**, so a build run starts in seconds.

## Build the image

The installer media is not in this repo. Populate `media/` from a local copy of
the media first (the repo is expected to live next to it):

```bash
./scripts/prepare-media.sh          # media/cd <- ../vb6studio_disk1
                                    # media/sp6 <- ../VB6_Services_Packs/vs6sp6setup
./build.sh                          # docker build -t vb6-builder:sp6 .
```

## Build a project

Mount the project tree at `/work` and an output directory at `/out`:

```bash
docker run --rm \
  -v "/path/to/MyProject:/work" \
  -v "/path/to/out:/out" \
  vb6-builder:sp6
```

The entrypoint (`build-project.sh`) then:

1. Finds the `.vbp` under `/work` (or uses `VBP_NAME`). Fails loudly if there
   is more than one and none was named.
2. Copies the tree to a scratch dir so the source mount stays untouched.
3. Registers COM components (see below).
4. Runs `wine VB6.EXE /make <project> /outdir <scratch>`.
5. Copies the resulting EXE to `/out` and prints its path and size.

### Environment

| Variable | Default | Meaning |
|---|---|---|
| `VBP_PATH` | `/work` | Directory containing the project |
| `VBP_NAME` | auto-discover | Project file name, e.g. `MyApp.vbp` |
| `VBP_OUTPUT` | `ExeName32` | Output EXE name |
| `VBP_OUTDIR` | scratch dir | VB6 `/outdir` |
| `VBP_DEFINES` | – | Conditional compilation, `name=value[,..]` |
| `VBP_EXTRA_COMPONENTS` | `/components` | Directory of `.ocx`/`.dll` to register |
| `VBP_COLLECT` | `/out` | Where the built EXE is copied |
| `VBP_SCRATCH` | `/build` | Writable build copy |

## What works, and what does not

Verified against this image:

| Dependency kind | Works | Notes |
|---|---|---|
| `.bas` standard modules | ✅ | |
| `.cls` class modules | ✅ | |
| `.frm` forms (no ActiveX controls) | ✅ | |
| Plain COM / ActiveX **DLLs** (e.g. Chilkat) | ✅ | Must be registered from `system32` |
| ActiveX **controls** on a form (`MSFLXGRD`, `MSWINSCK`, …) | ❌ | Cannot be instantiated under Wine |

Two gotchas worth knowing, both of which cost real debugging time:

- **Source files must use CRLF line endings.** VB6 silently fails to load a
  `.bas`/`.cls`/`.frm` saved with LF-only endings (the error is usually
  `'…' could not be loaded`, or a bogus `Sub or Function not defined`).
- **Register components from `system32`, not an arbitrary directory.** A
  registration whose path is not a system directory crashes the VB6 IDE at
  startup (`Unexpected error; quitting`), even for a plain COM DLL.
  `register-components.sh` handles this.

The practical consequence is that **projects whose forms host ActiveX controls
cannot be built here**. Making such a project buildable means removing the
control (replace the grid/list/winsock usage with plain code), which is what
the OMR project did.

## Layout

```
Dockerfile                 image definition
entrypoint.sh              -> /usr/local/bin/build-project.sh (the build driver)
build.sh                   convenience wrapper for `docker build`
scripts/
  prepare-media.sh         copy local VS6/SP6 media into media/
  install-vb6.sh           install VB6 + SP6 into the Wine prefix
  register-base.sh         register the SP6 redistributable controls
  register-components.sh   register a project's .ocx/.dll (from system32)
  wine-path.sh             POSIX -> Wine path helper
vendor/
  telyn_VB6.STF            setup response file used by install-vb6.sh
  vb98ent_minimal.stf      alternative (minimal) response file
  vb6setup.ps1             reference: Windows-side installer script
media/                     install media (gitignored)
```
