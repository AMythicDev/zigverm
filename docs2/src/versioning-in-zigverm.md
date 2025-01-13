# Versioning in zigverm
zigverm offers quite a bit of flexiblity for what versions are installed and how they can be updated.

## Fixed Versions
These include complete version codes such as `0.13.0`, `0.12.1`, `0.12.0` etc. They are installed once and never updated by zigverm.

## Fixed Minor Versions
These include partial version codes such as `0.13`, `0.12` etc. When installing/updating these types of versions, the latest patch
release for that specific minor version is installed. 

## `master`
This special version is provided by Zig itself and it closely follows the upstream Zig.

## `stable`
This special version is provided by zigverm and it installs whatever the latest stable release of Zig is right now.
When installing zigverm using the automatic installers, it will automatically install this version for you.
