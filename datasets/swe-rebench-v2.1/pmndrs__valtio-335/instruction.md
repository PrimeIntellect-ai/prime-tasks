This library doesn't seem to be glitch free?
First of all, thanks for sharing this very nice library!

I was doing some experiments, and I noticed that unlike most "push/pull functional reactive programming" libraries, this library is not glitch free, e.g. the callbacks of derived computations can be called with out-of-sync values, producing intermediate invalid results, and can be invoked multiple times per "leaf node" change, which can be inefficient in large "dataflow graphs".

Is this by design? [HIDDEN]

Code example at https://stackblitz.com/edit/react-sqyzte

```
import React from "react";
import "./style.css";

import { proxy, useSnapshot } from 'valtio'

import { derive } from 'valtio/utils'

const state = proxy({ value: 0 });

// derived1 = state
const derived1 = derive({
  value: (get) => get(state).value,
})

// derived1 = derived2
const derived2 = derive({
  value: (get) => get(derived1).value,
})

// derived3 = state + derived1 - derived2 = state + derived1 - derived1 = state + 0 = state
const derived3 = derive({
  value: (get) => {
    // notice in the console that this callback is invoked TWICE per state update.
    const v0 = get(state).value;
    const v1 = get(derived1).value;
    const v2 = get(derived2).value; // notice in the console that v2 is out-of-sync in the first callback invocation
    const r = v0 + (v1 - v2);
    // notice the glitches in the console
    // when state is changed, this callback is invoked TWICE with out-of-sync values.
    // glitches make debugging really hard, and can cause invalid intermediate values like NaN, div by zero, etc...
    console.log(`v0=${v0} v1=${v1} v2=${v2} => r=${r}`);
    return r;
  }
})


export default function App() {
  const snap = useSnapshot(derived3)
  return (
    <div>
      <code>{snap.value}</code>
      <br/>
      <button onClick={() => ++state.value}>+1</button>
    </div>
  );
}
```

### Additional contract requirements

When a leaf value changes, derived computations must observe dependency values from the same update rather than produce an intermediate invalid result. A derived computation must not be invoked more than once as a consequence of propagation from a single leaf-node change.
