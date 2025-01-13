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
