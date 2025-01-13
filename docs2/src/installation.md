# Installation

## For Linux and MacOS (x86_64/aarch64)

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

## For Windows
> An automatic installer for Windows is certainly planned however no work has been done for it yet.

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


