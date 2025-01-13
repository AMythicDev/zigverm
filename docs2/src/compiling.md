# Compiling

## Requirements
- Zig >= 0.12.0. Zig master releases are not supported and may give errors when compiling.
- libc on non-Windows systems. Can be provided by Zig itself, if available for the platform.
- `git`, if you want to compile the latest commit or you want to develop `zigverm`.

## To compile:
- Clone the repo or download a source archive depending on if you want to compile the latest `main`
  branch or a release.
  Clone command:
  ```sh
  git clone github.com/AMythicDev/zigverm.git
  ```
- Extract the archive if you downloaded a tarball and `cd` into the new directory.
- Run the following command
  ```
  zig build --release=safe
  ```

- If you are devloping `zigverm`, you can omit the `--release=safe` flag.
- You will have `zigverm` and `zig` executables in the `zig-out/bin/` directory
- Now create a new directory named `zigverm` under your home directory. See [Non-trivial zigverm Root](./non-trivial-zigverm-root.md) if you want a
  different zigverm root directory.
- Now create the following folder structure in your new `zigverm` directory.
  ```
  .
  ├── bin
  ├── downloads
  └── installs
  ```

- Copy `zigverm` and `zig` to the `bin/` folder.
- Optioally you can add the `zigverm/bin` directory to your `PATH` enviroment variable if you want to run zigverm and zig from
anywhere.



