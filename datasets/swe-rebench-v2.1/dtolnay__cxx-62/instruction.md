Decide header include path
The current setup exposes our C++ header as:

```cpp
#include "cxxbridge/cxxbridge.h"
```

This isn't great because of the repetition, and also because all the symbols in the header are namespaced under `rust::` so an include path with rust in the name somewhere may make more sense.

Something like:

- `#include "cxxbridge/rust.h"`
- `#include "rust/cxxbridge.h"`
- `#include "rust/cxx.h"`

### Additional contract requirements

- The public C++ header must be includable as `#include "rust/cxx.h"`.
