# Changelog
This file documents all changes made to the project and is updated before each release.

## v0.3.0 [2024-06-26]
### Changed
- **BREAKING CHANGE** Renamed zigvm to zigverm

### Fixed
- Fix all memoery leaks prosent in the common module 

## v0.2.0 [2024-06-13]
### Added
- Add support for continuing download if thers's a interrupt in between a download
- Add support for updating master, stable and x.y releases to latest point releases.

## Changed
- Use a better progress bar

## Fixed
- Fixed the zig executable not propagating the correct exit code of the child zig executable.
- Fix removing a release prints a error log on success.
- Fix automatic install script cannot find shell.

## v0.1.0 [2024-05-27]
- Initial release with preliminary support
