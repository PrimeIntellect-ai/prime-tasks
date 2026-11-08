duplicate export name `57` already defined when importing multiple semver versions
Using the latest wasi-sdk pacakge built with the fix from https://github.com/bytecodealliance/wasm-tools/issues/1774 (https://github.com/WebAssembly/wasi-sdk/actions/runs/11129514597) I still get an error when building a wasm component with `wasi:io/poll@0.2.0` and `wasi:io/poll@0.2.1` I get the following error:

```
-- Build files have been written to: /home/jstur/projects/runtime/artifacts/bin/native/net10.0-wasi-Debug-wasm
  [ 14%] Linking C executable dotnet.wasm
EXEC : error : failed to encode component [/home/jstur/projects/runtime/src/mono/wasi/wasi.proj]

  Caused by:
      0: failed to validate component output
      1: duplicate export name `57` already defined (at offset 0xdf82f5)
```

```
cat /home/jstur/wasi-sdk-nightly/VERSION
24.9gcec5cf4f6cf3
wasi-libc: 1b19fc65ad84
llvm: a4bf6cd7cfb1
llvm-version: 19.1.0
config: f992bcc08219
```
