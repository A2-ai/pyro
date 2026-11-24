# pyro 0.1.2

## Breaking Changes

* `run_python_script()` now calls `stderr_callback` once per line, with the line ending removed. Callbacks written for raw chunks need to add their own newline. Before this a line could be split across two calls, which broke filtering on level tags like `[DEBUG]`.

## Bug Fixes

* `initialize_python()` now accepts `~` and relative paths for `venv_dir`, `pyproject_dir`, and `options("venv_dir")`. These used to fail in the setup script or put `.venv` in the wrong folder.
* Pressing Enter at the `Continue? [Y/n]` prompt now means yes. It used to error with "Must enter Y or n."
* The prompt is now a single line, so the cursor lands after the question in RStudio instead of in the middle of it.

## Minor Improvements

* `initialize_python()` prints the project root once, then refers to files relative to it (`pyproject.toml`, `.venv`).
* Setup script output streams as it happens instead of printing in one block at the end.

# pyro 0.1.1

## Bug fixes

* The uv setup scripts no longer report "matches required version" when an existing `uv` is reused without a pin set. Since `initialize_python()` adopts the installed version when `getOption("uv.version")` is unset, that comparison was tautological. The message now reads "Using existing uv X.Y.Z" in both the bash and PowerShell installers.

# pyro 0.1.0

Initial release.

## Features

* `initialize_python()` installs `uv` if missing, seeds a project `pyproject.toml` on first run, runs `uv lock`, and materializes `.venv/` via `uv sync`. Prompts the user before touching their machine.
* `write_group_to_pyproject()` idempotently upserts a dependency group into the project's `pyproject.toml`. User-pinned versions are preserved on conflict.
* `run_python_script()` runs a Python script inside the project venv via `processx::run()`, with optional `PYTHONPATH`, `stderr_callback`, and `verbose_env` passthrough.
* `get_venv_uv_paths()`, `get_uv_path()`, `get_uv_version()`, and `get_proj_dir()` expose the locations and versions needed to call into the venv from R.

## Conventions

* The project's `pyproject.toml` is the source of truth; `pyro` seeds it on first init but never rewrites existing pins. Drift from the bundled reference spec is surfaced as information, not corrected.
* `venv_dir` refers to the parent directory of `.venv/` (the project root). `pyproject_dir` may point at an alternate location for non-default project layouts.
* `getOption("venv_dir")` caches the resolved project root across calls within an R session.
* `getOption("uv.version")` pins the `uv` binary version; falls back to `0.7.8` when unset on a clean machine.

## Platforms

* Unix-like systems use the bundled `uv_setup.sh` installer.
* Windows uses the bundled `uv_setup.ps1` (PowerShell) installer.
