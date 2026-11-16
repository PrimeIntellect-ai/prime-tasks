Support DWARFv5 source code embedding extension
<!--
Please provide some context on what problem you are trying to solve and how this feature is going to help.

-->

DWARFv5 has an extension for embedding program source code directly into the debug info sections: https://dwarfstd.org/issues/180201.1.html

`symbolic` is not currently aware of this, and can't provide source code for ELF files:
https://github.com/getsentry/symbolic/blob/2b0af545c31b7a24d7c07e8a137272bce5cafa7e/symbolic-debuginfo/src/elf.rs#L536-L537

It'd be nice to have this as a convenient alternative to source bundles. Clang supports it through a [`-gembed-source` flag](
https://clang.llvm.org/docs/ClangCommandLineReference.html#cmdoption-clang-gembed-source
) but other toolchains (Rust) don't have similar flags yet as far as I can tell.

For more information, here's the LLVM implementation of the DWARF bits: https://reviews.llvm.org/D42765

I'll probably take a stab at implementing this but wanted to open an issue first :slightly_smiling_face:
