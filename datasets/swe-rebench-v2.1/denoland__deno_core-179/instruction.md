`op_close` with `WasmStreamingResource` invokes JS from an op while `OpState` is borrowed
I get a panic with the following code

```js
const makeEnv = (...envs) => {
  return new Proxy(envs, {
    get(_target, prop, _receiver) {
      console.log("get", prop); // remove this and it won't panic
      for (const env of envs) {
        if (Object.hasOwnProperty.call(env, prop)) {
          return env[prop];
        }
      }
      return (...args) => {
        console.error(`NOT IMPLEMENTED: ${prop}`, args);
      };
    },
  });
};

const { instance } = await WebAssembly.instantiateStreaming(
  fetch(new URL("./static/main.wasm", import.meta.url)),
  {
    env: makeEnv({
      printf: function () {
        console.log(arguments);
      },
    }),
  },
);

instance.exports.output(0);
```

```
============================================================
Deno has panicked. This is a bug in Deno. Please report this
at https://github.com/denoland/deno/issues/new.
If you can reliably reproduce this panic, include the
reproduction steps and re-run with the RUST_BACKTRACE=1 env
var set and include the backtrace in your report.

Platform: macos x86_64
Version: 1.36.4
Args: ["deno", "run", "-A", "script.js"]

thread 'main' panicked at 'already mutably borrowed: BorrowError', ext/node/global.rs:273:27
stack backtrace:
   0: _rust_begin_unwind
   1: core::panicking::panic_fmt
   2: core::result::unwrap_failed
   3: deno_node::global::current_mode
   4: deno_node::global::getter
   5: <extern "C" fn(A0,A1) .> R as v8::support::CFnFrom<F>>::mapping::c_fn
   6: __ZN2v88internal12_GLOBAL__N_134GetPropertyWithInterceptorInternalEPNS0_14LookupIteratorENS0_6HandleINS0_15InterceptorInfoEEEPb
   7: __ZN2v88internal6Object11GetPropertyEPNS0_14LookupIteratorEb
   8: __ZN2v88internal6LoadIC4LoadENS0_6HandleINS0_6ObjectEEENS2_INS0_4NameEEEbS4_
   9: __ZN2v88internal29Runtime_LoadNoFeedbackIC_MissEiPmPNS0_7IsolateE
note: Some details are omitted, run with `RUST_BACKTRACE=full` for a verbose backtrace.
```
