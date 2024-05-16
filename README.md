# zigvm
Version manager for the Zig Programming Language.

It lets you install, remove and manage your Zig installation.

**zigvm is in early stages of its development, it can do [basic things](#supported-features) and platform support 
may not be on par with other version managers. If you encounter issues or want to request a feature
be sure to drop a issue on the GitHub issue tracker.**

## Platform Support
Legend:  
🎉 - Binary releases + automatic installer available  
💪 - binary releases available  
❌ - No binary releases. Compile for your own thing  
\- - Not applicable

| OS/Arch | x86_64 | x86 | aarch64 | armv7a | riscv64 |
|---------|--------|-----|---------|--------|---------|
| Windows |   💪   |  💪 |    ❌   |   ❌   |    -    |
| Linux   |   🎉   |  🎉 |    🎉   |   ❌   |    ❌   |  
| MacOS   |   🎉   |  -  |    🎉   |   -    |    -    |

## Installation
### For Linux and MacOS (x86_64+aarch64)
You can use this automated install script which will install zigvm along with the latest version of Zig

```sh
curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/AMythicDev/zigvm/main/scripts/install.sh | sh
```

By default it will create `$HOME/.zigvm` directory as the root folder for zigvm. You can customize this by setting this
by setting the `ZIGVM_ROOT_DIR` to the directory where you want to install zigvm. Make sire you add the `ZIGVM_ROOT_DIR`
in your shell config otherwise zigvm would not be able to locate the installation folder.

The script will also put the installation directory's `bin` folder to your `$PATH` variable. For this it will append
a line to your `$HOME/.profile` and `$HOME/.bashrc` or `$HOME/.zshrc` depending on your default login shell.

### For Windows
* Create the following folder structure in `C:\Users\[YOU-USERNAME]\.zigvm`:
```
.
├── bin
├── downloads
└── installs
```
* Download the latest release for Windows from GitHub, rename it to `zigvm.exe` and put it in the `bin` directory.

## Supported Features
- [x] Install versions (master, stable, x.y.z)
- [x] Remove versions
- [x] List down installed versions

## License
`zigvm` is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file.
