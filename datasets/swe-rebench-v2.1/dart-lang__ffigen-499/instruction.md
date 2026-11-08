C uintptr_t is being mapped to ffi.UnsignedLong instead of ffi.UIntPtr
Hello. I discovered unexpected behavior

`temp.h`
```
#include <stdint.h>

uintptr_t temp_u();
intptr_t temp_i();
```

using ffigen on linux I get this.

```
...
  int temp_u() {
    return _temp_u();
  }

  late final _temp_uPtr =
      _lookup<ffi.NativeFunction<uintptr_t Function()>>('temp_u');
  late final _temp_u = _temp_uPtr.asFunction<int Function()>();

  int temp_i() {
    return _temp_i();
  }

  late final _temp_iPtr =
      _lookup<ffi.NativeFunction<ffi.IntPtr Function()>>('temp_i');
  late final _temp_i = _temp_iPtr.asFunction<int Function()>();

  typedef uintptr_t = ffi.UnsignedLong;
...
```

for some reason `intptr_t` converts correctly to `ffi.IntPtr`
but
`uintptr_t` is converted to `typedef uintptr_t = ffi.UnsignedLong`;
Why is `uintptr_t` not converted to `ffi.UIntPtr`?

`ffi.UnsignedLong` is 64 for linux but 32 for windows, which causes errors when using generated dart code by linux on windows.

### Additional contract requirements

- When a C header uses `uintptr_t` (for example as a return type or a parameter type), the generated Dart bindings must use the pointer-sized unsigned FFI type `ffi.UintPtr` rather than `ffi.UnsignedLong`.
