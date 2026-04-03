# zigverm: User Guide

zigverm is a Zig version manager. It installs, updates, and switches Zig toolchains per directory, so different projects can pin different Zig versions without changing your global setup.

## Installation

Refer to the [installation](https://github.com/AMythicDev/zigverm/blob/main/README.md#installation) section for platform-specific steps and compiling instructions.

## Version labels

- `master` refers to the Zig master builds.
- `stable` refers to the latest Zig release. Zig has not reached a stable version yet, so this is the most recent release. This label will be renamed to `latest` in the future.

## Installing and removing Zig versions

- Install the latest release

```sh
zigverm install stable
```

- Install the Zig master build

```sh
zigverm install master
```

- Install a specific version

```sh
zigverm install 0.12.0
```

- Install the most recent patch release for a minor version

```sh
zigverm install 0.12
```

- Remove a version

```sh
zigverm remove 0.12.0
```

## Updating Zig versions

- Update all installed versions

```sh
zigverm update
```

- Update a specific track (master, stable, or a minor line)

```sh
zigverm update master
zigverm update stable
zigverm update 0.12
```

Specific versions installed as full semantic versions (for example, `0.10.1`) are not updated.

## Managing overrides

Overrides let you pin a Zig version for a directory. All subdirectories inherit the same version unless they also have an explicit override.

- Override the current directory

```sh
zigverm override 0.12.0
```

- Override a specific directory

```sh
zigverm override ~/some/path 0.12.0
```

- Override the default version

```sh
zigverm override default 0.12.0
```

The `default` label acts as the fallback version when no override is present for a directory. It can be changed with `zigverm override default [VERSION]` but it cannot be removed.

- Remove an override

```sh
zigverm override-rm ~/some/path
```

Any override can be removed with `zigverm override-rm` except for `default`.

## Info and documentation commands

- Show zigverm installation info and the active version for the current directory

```sh
zigverm info
```

- Open the Zig language reference for the active or specified version

```sh
zigverm reference
zigverm reference 0.12.0
```

- Open the Zig standard library documentation for the active or specified version

```sh
zigverm std
zigverm std 0.12.0
```

## Updating zigverm itself

```sh
zigverm update-self
```
