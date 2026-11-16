`-v` or `--version` should continue linking if inputs are provided
This one was tricky to diagnose.

CMake during initial configuration tries to find out the compiler's ABI, but that fails with wild: `-- Detecting C compiler ABI info - failed`. Turns out it will try to link the test executable like that: `cc -v -Wl,-v CMakeFiles/cmTC_68e1c.dir/CMakeCCompilerABI.c.o -o cmTC_68e1c` and `-Wl,-v` is the problem here as wild will just print the version and exit.

Minimized version with ld.bfd:
```
❯ rm -f /tmp/wild_test_file && ld -lc -o /tmp/wild_test_file -v && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
GNU ld (GNU Binutils) 2.43.1
ld: warning: cannot find entry symbol _start; not setting start address
exists

❯ rm -f /tmp/wild_test_file && ld /usr/lib/libc.a -o /tmp/wild_test_file -v && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
GNU ld (GNU Binutils) 2.43.1
ld: warning: cannot find entry symbol _start; not setting start address
exists

❯ rm -f /tmp/wild_test_file && ld /usr/lib/libc.a -o /tmp/wild_test_file --version && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
GNU ld (GNU Binutils) 2.43.1
Copyright (C) 2024 Free Software Foundation, Inc.
This program is free software; you may redistribute it under the terms of
the GNU General Public License version 3 or (at your option) a later version.
This program has absolutely no warranty.
missing
```
With wild:
```
❯ rm -f /tmp/wild_test_file && ./ld -lc -o /tmp/wild_test_file -v && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
Wild version 0.3.0 (compatible with GNU linkers)
missing

❯ rm -f /tmp/wild_test_file && ./ld /usr/lib/libc.a -o /tmp/wild_test_file -v && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
Wild version 0.3.0 (compatible with GNU linkers)
missing

# This one is correct
❯ rm -f /tmp/wild_test_file && ./ld /usr/lib/libc.a -o /tmp/wild_test_file --version && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
Wild version 0.3.0 (compatible with GNU linkers)
missing

# Bonus, there is one more discrepancy with ld.bfd; without -v
❯ rm -f /tmp/wild_test_file && ./ld /usr/lib/libc.a -o /tmp/wild_test_file && test -e /tmp/wild_test_file && echo "exists" || echo "missing"
Error: Failed to activate <prelude>

Caused by:
    Missing _start symbol
missing
```

Basically wild should print the version and proceed with linking when `args` field of `Args` structure is not empty and `-v` was passed.
