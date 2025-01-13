# Zigverm
Zigverm is a version manager for the [Zig](https://ziglang.org) programming language.

Currently Zig does not have any official version manager and zigverm fills this space by providing a solid version manager from the ground up
written in Zig itself.

## Features
- Easy installation with automatic installers for various platforms
- Manage Zig installations
- Manage global and per-directory overrides
- Open the offline language reference and standard library docs for a Zig version
- Self-update
- Tries to maintain strong compatiblity with the wider zig ecosystem (`zls`, `zig.vim`)

## Platform support
Although zigverm supports all mainstream platforms, it does not support everything that Zig can be installed on. We intend to support more
platforms in the future however our current focus is to reach a good feature set.

Here's the current platform support matrix:
Legend:  
🎉 - Binary releases + automatic installer available  
💪 - Binary releases available  
❌ - No binary releases. Maybe supported later. Requires [compiling](#compiling)  
\- - Not applicable

| OS/Arch | x86_64 | x86 | aarch64 | armv7a | riscv64 |
| ------- | ------ | --- | ------- | ------ | ------- |
| Windows | 💪     | 💪  | ❌      | -      | -       |
| Linux   | 🎉     | 🎉  | 🎉      | ❌     | ❌      |
| MacOS   | 🎉     | -   | 🎉      | -      | -       |

## Contributing

## License
All works to zigverm are available licensed under the [Apache License 2.0](https://github.com/AMythicDev/zigverm/blob/main/LICENSE)
unless explicitly mentioned.
