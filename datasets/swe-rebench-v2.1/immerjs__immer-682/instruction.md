Clearing empty Set&Map should be noop
## 🐛 Bug Report
## To Reproduce

```
const { produce, enableMapSet } = require("immer");
enableMapSet();
const map = new Map();
const newMap = produce(map, draft => { draft.clear(); });
map === newMap
```
## Observed behavior

false
## Expected behavior

true
## Environment
- **Immer version:**
- [x] I filed this report against the _latest_ version of Immer
- [x] Occurs with `setUseProxies(true)`
- [x] Occurs with `setUseProxies(false)` (ES5 only)
