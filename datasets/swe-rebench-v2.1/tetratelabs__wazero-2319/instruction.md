fd_fdstat_set_flags can silently change a fd's number
**Describe the bug**
[HIDDEN], leaving the file with potentially the wrong file descriptor.

**To Reproduce**
```
package main

import (
        "io"
        "log"
        "os"
        "syscall"
)

func main() {
        f1, err := os.Open("/file")
        if err != nil {
                log.Fatal(err)
        }
        f2, err := os.Open("/file")
        if err != nil {
                log.Fatal(err)
        }
        f1.Close()
        syscall.SetNonblock(int(f2.Fd()), true)
        if _, err := io.ReadAll(f2); err != nil {
                log.Fatal(err)
        }
}
```

```
$ echo foo > file
$ wazero run -mount=.:/ main.wasm
2024/09/20 23:50:44 read /file: Bad file number
```

This program should read from "file", but the read fails because f2's FD has changed. (The "syscall.SetNonblock" is necessary to trigger the correct write path here.)

I initially thought this might be exploitable to write to files in read-only mapped directories, but that doesn't seem to be the case. You can write to an unexpected writeable file, though.

**Environment (please complete the relevant information):**

- Go version: master
- wazero Version: master
- Host architecture: darwin_arm64

### Additional contract requirements

When changing file flags requires reopening an open file, the operation must not retarget the handle if its path no longer names the same underlying file. In that case it must report a nonzero errno and leave a different file at that path untouched.
