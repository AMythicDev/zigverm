# Changelog
This file documents all changes made to the project and is updated before each release.

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
