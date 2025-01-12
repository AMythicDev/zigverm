# zigverm

zigverm is a version manager for the [Zig](https://ziglang.org) programming Language. It lets you install Zig and further manage your installation.

## Platform Support

Legend:  
🎉 - Binary releases + automatic installer available  
💪 - binary releases available  
❌ - No binary releases. Maybe supported later. Requires [compiling](#compiling)  
\- - Not applicable

| OS/Arch | x86_64 | x86 | aarch64 | armv7a | riscv64 |
| ------- | ------ | --- | ------- | ------ | ------- |
| Windows | 💪     | 💪  | ❌      | -      | -       |
| Linux   | 🎉     | 🎉  | 🎉      | ❌     | ❌      |
| MacOS   | 🎉     | -   | 🎉      | -      | -       |

## Installation

### For Linux and MacOS (x86_64/aarch64)

You can use this automated install script which will install zigverm along with the latest version of Zig

```sh
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/AMythicDev/zigverm/main/scripts/install.sh | bash
```

By default it will create `$HOME/.zigverm` directory as the root folder for zigverm. You can customize
this by setting this by setting the `ZIGVERM_ROOT_DIR` to the directory where you want to install
zigverm. Make sire you add the `ZIGVERM_ROOT_DIR` in your shell config otherwise zigverm would not be able
to locate the installation folder.

The script will also put the installation directory's `bin` folder to your `$PATH` variable. For
this it will append a line to your `$HOME/.profile` and your shell's rc file. The file for each
shell supported is listed below:

- Bash: `$HOME/.bashrc`
- Zsh: `$HOME/.zshrc`
- Fish: `$XDG_CONFIG_HOME/fish/config.fish`, if not set then uses `$HOME/.config/fish/config.fish`

### For Windows

- Create the following folder structure in `C:\Users\[YOU-USERNAME]\.zigverm`:

```
.
├── bin
├── downloads
└── installs
```

- Download the latest release for Windows from GitHub and extract it.
- Copy `zigverm.exe` and `zig.exe` to the `bin/` folder.
- Add the `bin` directory to your `PATH` enviroment variable

### Compiling

Requirements:

- Zig >= 0.12.0. See [this](https://github.com/AMythicDev/zigverm#note-for-zig--v014) for Zig v0.14.
- libc on non-Windows systems. Can be provided by Zig itself, if available for the platform.
- `git`, if you want to compile the latest commit or you want to develop `zigverm`.

Now to compile:

- Clone the repo or download a source archive depending on if you want to compile the latest `main`
  branck or a release.
- Extract the archive and change into the extracted directory.
- Run the following command

```
zig build --release=safe
```

- If you are devloping `zigverm`, you can omit the `--release=safe` flag.
- You will have `zigverm` and `zig` in `zig-out/bin/` directory
- Lastly follow the same steps [for windows](#for-windows)

#### Note for Zig >= v0.14
There have been some API changes in Zig v0.14 (not released yet) which makes zigverm fail 
to compile on these versions of Zig. All the changes required to fix this is issue is being 
tracked in [this](https://github.com/AMythicDev/zigverm/pull/2) PR. It will be merged into 
main once this version of Zig comes out.

## Features

- [x] Install versions (master, stable, x.y x.y.z)
- [x] Continue download if previously interrupted
- [x] Remove versions
- [x] List down installed versions
- [x] Update zigverm itself
- [x] Manage default and per-directory version overrides
- [x] Open the language reference and standard library docs (even when offline).
- [x] Tries to maintain strong compatiblity with the wider zig ecosystem (`zls`, `zig.vim`)

## Docs

Read the [quick guide](./docs/quick-guide.md)

## License

`zigverm` is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file.
