Error: Symbol is in a section that we didn't load. Symbol: symbol `compute_value10` (76 local=5) in file #1025 (4/1) (/tmp/cc3sE5xh.o) (IFUNC | CAN_BYPASS_GOT) Section: `.text`
Noticed while isolating another issue:

```
$ cat snippet.c
static int return10() {
    return 10;
}

int compute_value10(void) __attribute__((ifunc ("resolve_compute_value10")));

static void *resolve_compute_value10(void) {
    return return10;
}
$ cat snippet2.c
int main() {
  return 0;
}
$ gcc snippet*.c -B ~/Programming/wild
WARNING: wild: --plugin /usr/lib64/gcc/x86_64-suse-linux/14/liblto_plugin.so is not yet supported
Error: Symbol is in a section that we didn't load. Symbol: symbol `compute_value10` (76 local=5) in file #1025 (4/1) (/tmp/ccdNDbYx.o) (IFUNC | CAN_BYPASS_GOT) Section: `.text`
collect2: error: ld returned 255 exit status
```
