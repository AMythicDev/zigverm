# Changelog

This file documents all changes made to the project and is updated before each release.

## v0.7.2 [2025-12-15]
### Fixed
- Windows binary releases being published without `.exe` extension

## v0.7.1 [2025-09-26]
### Fixed
- `update-self` now works on all systems

### Dependencies
- Upgrade to zip.zig v0.3.2

## v0.7.0 [2025-09-24]
### Changed
- Requires Zig master to build correctly

### Dependencies
- Upgrade to zip.zig v0.3.1

## v0.6.2 [2025-02-04]
### Fixed
- JSON parser returns syntax error when parsing large overrides.json file

## v0.6.1 [2025-02-01]
### Fixed
- Fix download progress bar stuck at 99%
- Fix override command not recognizing `default` as a keyword

## v0.6.0 [2025-01-25]
### Added
- The LICENSE and README file will now be included with each release.
- Override the zig version for a specific command by writing `zig @<version> ...`
- Use `multiprocessing` module in `z.py` to build parallel releases

### Changed
- `zigverm override-rm` requires the directory path to be explicit given.
- `zigverm override`/`zigverm override-rm` can now take relative directory paths.
- Overhaul the download progress bar

### Fixed
- Tests not being run from `common/tests.zig` file
- `master` versions not being updated to `to_update` being set to false;

## v0.5.1 [2024-11-29]

### Fixed

- Fixed various bugs with terminal progress bar
- Fixed bug where calling remove on an installed version would quit zigverm with a `Version not installed. Quitting` message.

## v0.5.0 [2024-11-13]

### Added

- Update zig versions only if they need an update
- Add CI to test install script
- Report versions that were updated

### Fixed

- Do not add to PATH if the bin dir already exists in PATH
- Correct detection of OS and architecture in install script

## v0.4.0 [2024-09-19]

### Added

- Support to update zigverm itself

### Fixed

- Version and helptext printed to stderr instead of stdout
- Retry download if hashes for download tarballs do not match.
- Errors in detecting OS in install.sh

## v0.3.1 [2024-06-28]

### Fixed

- Segfault when overriding
- Architecture detection errors in install.sh on non-darwin based aarch64 systems
- Enviroment variable for root is not `ZIGVERM_ROOT_DIR`
- Potential memory issues in `CommonPaths`

## v0.3.0 [2024-06-26]

### Added

- `langref` and `std` subcommands to open the language reference and standard library for the active version or
  a specified version.

### Changed

- **BREAKING CHANGE** Renamed zigvm to zigverm.

### Fixed

- Fix all memoery leaks prosent in the common module.
- Wrong tarball downloaded when running install.sh under Rosetta2.
- Fix tarball not downloading on `aarch64` macs due to `uname -m` reporting it as `arm64`

## v0.2.0 [2024-06-13]

### Added

- Add support for continuing download if thers's a interrupt in between a download.
- Add support for updating master, stable and x.y releases to latest point releases.

## Changed

- Use a better progress bar

## Fixed

- Fixed the zig executable not propagating the correct exit code of the child zig executable.
- Fix removing a release prints a error log on success.
- Fix automatic install script cannot find shell.

## v0.1.0 [2024-05-27]

- Initial release with preliminary support
