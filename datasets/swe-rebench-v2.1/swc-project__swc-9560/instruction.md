@swc/core's binary does not handle folders with `.js` suffix well
### Describe the bug

I found that SWC mistakenly treats a folder with the `.js` suffix as a file, which introduces this bug:

```
$ ./swc-darwin-arm64-1.7.26 compile .
Error: Failed to open file ./vendor/chart.js

Caused by:
    Is a directory (os error 21)
```

Note that the binary is downloaded from the GitHub Releases:

```
wget https://github.com/swc-project/swc/releases/download/v1.7.26/swc-darwin-arm64 -O swc-darwin-arm64-1.7.26 && chmod +x swc-darwin-arm64-1.7.26
```


### Input code

_No response_

### Config

_No response_

### Playground link (or link to the minimal reproduction)

https://github.com/pan93412/swc-minimum-repro

### SWC Info output

```
    Operating System:
        Platform: darwin
        Arch: arm64
        Machine Type: arm64
        Version: Darwin Kernel Version 24.0.0: Mon Aug 12 20:52:41 PDT 2024; root:xnu-11215.1.10~2/RELEASE_ARM64_T6031
        CPU: (16 cores)
            Models: Apple M3 Max

    Binaries:
        Node: 20.17.0
        npm: 10.8.2
        Yarn: N/A
        pnpm: N/A

    Relevant Packages:
        @swc/core: N/A
        @swc/helpers: N/A
        @swc/types: N/A


    SWC Config:
        output: N/A
        .swcrc path: N/A

    Next.js info:
        output: N/A
```

### Expected behavior

It should be able to build. For example, when I rename `chart.js` to `charts`:

```
$ mv vendor/chart.js/ vendor/chartjs

$ ./swc-darwin-arm64-1.7.26 compile .
./vendor/chartjs/chart.js.min.js
console.log("hi chart.js");

./index.ts
console.log("Hello");
```

### Actual behavior

```
$ mv vendor/chartjs vendor/chart.js

$ ./swc-darwin-arm64-1.7.26 compile .
Error: Failed to open file ./vendor/chart.js

Caused by:
    Is a directory (os error 21)
```

### Version

1.7.26

### Additional context

_No response_

### Additional contract requirements

- When the CLI compiles a directory, it must only treat regular files as inputs. A
  subdirectory whose name ends with a supported source extension (for example a
  directory named `chart.js`) must be ignored instead of being opened as a file, so
  that `swc compile <dir>` exits successfully.


When compiling a directory, compile supported source files found in that directory and its nested directories. Ignore directories whose names have a supported source-file extension rather than attempting to compile them as files.
