Error: Failed to copy section  when linking libclang
On LLVM commit `f83726e6` when testing [wild-proxy](https://github.com/mati865/wild-proxy) by running `PATH=~/Projects/wild-proxy:$PATH CC=wild-gcc CXX=wild-g++ cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_BUILD_TYPE=Release -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ../llvm` and then `ninja` I expected it to pass, but it failed when linking.

Then also reproduced it using more typical setup:
```
❯ PATH=~/Projects/wild:$PATH cmake -DLLVM_ENABLE_PROJECTS=clang -DCMAKE_BUILD_TYPE=Release -G Ninja ../llvm

❯ PATH=~/Projects/wild:$PATH ninja libclang
...

Error: Failed to copy section ``.text._ZN12_GLOBAL__N_119ARMMachObjectWriter16recordRelocationEPN4llvm16MachObjectWriterERNS1_11MCAssemblerEPKNS1_10MCFragmentERKNS1_7MCFixupENS1_7MCValueERm`` from file lib/libLLVMARMDesc.a @ ARMMachObjectWriter.cpp.o (75777 (296/1))

Caused by:
    Direct relocation (R_X86_64_PC32) to dynamic symbol from non-writable section, but copy relocations are disabled. symbol `llvm::hexdigit(unsigned int, bool)::LUT` (8292 local=2107) in file #2304 (9/0) (lib/libclangAST.a @ ASTContext.cpp.o) (ADDRESS)
```

### Additional contract requirements

- When alternative definitions of the same symbol have differing visibilities and any of them is hidden or protected, the resolved symbol must not be preemptible: references to it from the output must bind directly, even when the selected definition has default visibility. Such references from non-writable sections must link successfully.
- A symbol that is protected in one of its definitions must remain exported as a dynamic symbol.
