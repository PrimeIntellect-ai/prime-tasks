Rust test `run-make/return-non-c-like-enum` fails
Running `PATH=~/Projects/wild:$PATH ./x.py t tests/run-make/return-non-c-like-enum/` fails with:
```
Error: Failed copying from <epilogue> to output file

Caused by:
    Internal error: Unexpected dynamic symbol definition from <not loaded>. symbol `__letf2` (15116 local=4) in file #21251 (83/3) (libnonclike.a @ compiler_builtins-ff3289faa9344fd9.compiler_builtins.b66d79b79bdb8f0f-cgu.028.rcgu.o) (ADDRESS | CAN_BYPASS_GOT)

Stack backtrace:
   0: anyhow::error::<impl anyhow::Error>::msg
   1: libwild::elf_writer::write_dynamic_symbol_definitions
   2: libwild::elf_writer::<impl libwild::layout::FileLayout>::write
...
```
I have no clue why, but readelf, objdump and nm don't report this symbol, unless the underlying object is extracted from the archive:
```
❯ readelf -Ws ./libnonclike.a | rg left2 || echo missing
missing

❯ ar x libnonclike.a compiler_builtins-ff3289faa9344fd9.compiler_builtins.b66d79b79bdb8f0f-cgu.028.rcgu.o

❯ readelf -Ws ./compiler_builtins-ff3289faa9344fd9.compiler_builtins.b66d79b79bdb8f0f-cgu.028.rcgu.o

Symbol table '.symtab' contains 5 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS compiler_builtins.b66d79b79bdb8f0f-cgu.028
     2: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT    5 .LCPI0_0
     3: 0000000000000000     0 SECTION LOCAL  DEFAULT    6 .text.__letf2
     4: 0000000000000000   177 FUNC    WEAK   HIDDEN     6 __letf2
```

Note: building Rust with wild requires not disabling `download-ci-llvm` before version script support is extended,
So, I'm also attaching the reproducer extracted with `WILD_SAVE_DIR`:

[rust-fail.tar.gz](https://github.com/user-attachments/files/19031060/rust-fail.tar.gz)
