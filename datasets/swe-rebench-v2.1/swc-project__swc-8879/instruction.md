swc tries to parse `//# sourceMappingURL` from inside a string variable
### Describe the bug

swc incorrectly tries to parse `//# sourceMappingURL` directive from inside of a string variable

The issue doesn't show up in playground, since the code does compile but when compiling in terminal, the error is written to console.


### Input code

```typescript
var a = "//# sourceMappingURL=[file].map"
```


### Config

```json
{
    "sourceMaps": "inline",
    "jsc": {
        "target": "es2021",
        "parser": {
          "syntax": "ecmascript"
        }
    }
}
```


### Playground link (or link to the minimal reproduction)

https://play.swc.rs/?version=1.4.14&code=H4sIAAAAAAAAAytLLFJIVLBVUNLXV1Yozi8tSk71TSwoyMxLDw3ysY1Oy8xJjdXLTSxQAgDDoVpaKQAAAA%3D%3D&config=H4sIAAAAAAAAA1WMQQqAMAwE732F5OxBPfoHHxFqkIrWkqSgiH%2B3rSK4l7C7szlNlQSyRbY0YBDoK3B%2BcZ6gfrpZbArPYkqgyBNpBkm6pmtfsHQBWYh%2FfH5%2FeMW9LOyKYtkFhQ%2B4nv17wMmwjXGhhCtHMpe5AeizYuOlAAAA

### SWC Info output

```
    Operating System:
        Platform: win32
        Arch: x64
        Machine Type: x86_64
        Version: Windows 10 Pro
        CPU: (8 cores)
            Models: Intel(R) Core(TM) i7-6700K CPU @ 4.00GHz

    Binaries:
        Node: 16.19.0
        npm: N/A
        Yarn: N/A
        pnpm: N/A

    Relevant Packages:
        @swc/core: 1.4.14
        @swc/helpers: N/A
        @swc/types: 0.1.6


    SWC Config:
        output: N/A
        .swcrc path: N/A

    Next.js info:
        output: N/A
```

### Expected behavior

No error in console

### Actual behavior

```
  ERROR  failed to read input source map: failed to parse inline source map url
[file].map"

Caused by:
    relative URL without a base
    at C:\Users\runneradmin\.cargo\registry\src\index.crates.io-6f17d22bba15001f\swc-0.273.25\src\lib.rs:385

Successfully compiled 1 file with swc.
var a = "//# sourceMappingURL=[file].map";

//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbInRlc3QuanMiXSwic291cmNlc0NvbnRlbnQiOlsidmFyIGEgPSBcIi8vIyBzb3VyY2VNYXBwaW5nVVJMPVtmaWxlXS5tYXBcIiJdLCJuYW1lcyI6WyJhIl0sInJhbmdlTWFwcGluZ3MiOiIiLCJtYXBwaW5ncyI6IkFBQUEsSUFBSUEsSUFBSSJ9

```

### Version

1.4.14

### Additional context

_No response_

### Additional contract requirements

- A `//# sourceMappingURL` directive must be ignored when it occurs inside a string value, including a template literal.
