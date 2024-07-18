## Quick Guide
### Installing/Removing versions
- Installing the stable version
NOTE: Zig does not have a stable release yet hence the usage of the word *stable* hereby is to purely mean **The most recent version of Zig**.
The main reason for using of the term is to avoid backwards compatiblity of `zigverm` when Zig itself reaches v1.0.
```sh
zigverm [install/remove] stable
```
- Installing the master version
```sh
zigverm [install/remove] master
```
- Installing a specific version
```sh
zigverm [install/remove] 0.12.0
```
- Installing the most recent patch version of specific minor version
```sh
zigverm [install/remove] 0.12
```

### Updating versions
- Update all installed versions
```sh
zigverm update
```
- Updating the stable version
```sh
zigverm update stable
```
- Updating the master version
```sh
zigverm update master
```
- Updating the most recent patch version of specific minor version
```sh
zigverm updating 0.12
```

### Managing overrides
zigverm can manage the Zig version to be used on per-directory basis through overrides. This allows you to use different versions of Zig in different projects.

- Overriding for the current directory
```
zigverm override 0.12.0
```

- Overriding for a specific current directory
```
zigverm override ~/some/path 0.12.0
```

- Overriding the default version
```
zigverm override default 0.12.0
```

- Removing override for the current directory
```
zigverm override-rm
```

- Removing override for a specific current directory
```
zigverm override-rm path/to/some/dir
```


Overrides follow inheritance meaning if you use override `/path/to/some/dir` to use Zig `0.10.1` then `/path/to/some/dir/inside/a/dir` will also
use `0.10.1` unless it is also explicitly overriden.

### Show details for the current installation of zigverm
This will show the directory where zigverm is installed along with the active version on the current directory. It will also list down 
all the installed versions of Zig.
```sh
zigverm info
```

### Open the language reference for the active Zig version
````sh
zigverm langref
````

### Open the standard library documentation for the active Zig version
````sh
zigverm std
````


Specific versions installs like `0.10.1` are not updated whatsoever.

