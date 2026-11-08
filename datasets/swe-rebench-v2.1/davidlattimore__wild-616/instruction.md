An ifunc test fails with `-pie`
The following test-case fails:
```c
#include <stdio.h>

void foo() {}
int bar() __attribute__((ifunc("resolve_bar")));
void *resolve_bar() { return foo; }
void *bar2 = bar;

int main() {
  printf("%p %p\n", bar, bar2);
}
```

```
❯ gcc /tmp/ifunc.c -c -fPIC && gcc ifunc.o -pie -B ~/Programming/wild
WARNING: wild: --plugin /usr/lib64/gcc/x86_64-suse-linux/14/liblto_plugin.so is not yet supported
Error: Failed copying from ifunc.o (768 (3/0)) to output file

Caused by:
    0: Failed to apply relocations in section `.data.rel` of ifunc.o
    1: Failed to apply relocation of type R_X86_64_64 to symbol `bar` (76 local=7) in file #768 (3/0) (ifunc.o) (IFUNC | CAN_BYPASS_GOT) at offset 0x0
    2: Insufficient .rela.dyn (relative) allocation. Setting WILD_VERIFY_ALLOCATIONS=1 might give more info
collect2: error: ld returned 255 exit status
```
