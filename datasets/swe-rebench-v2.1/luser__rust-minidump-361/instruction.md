crash address being read as 64-bit for 32-bit platforms
socc-pair --crash-id=[082a152f-05b4-4de9-943b-c30550211210](https://crash-stats.mozilla.org/report/index/082a152f-05b4-4de9-943b-c30550211210)

```diff
 : {
   crash_info: {
-    did not match
+    address: 0xe5e5e5e5
-    address: 0xffffffffe5e5e5e5
     crashing_thread: 25
     type: EXCEPTION_ACCESS_VIOLATION_READ
   }
```

(+ is breakpad, - is rust-minidump)

This crash report is from x86, so it's almost certain that rust-minidump is wrong here.

### Additional contract requirements

- The crash address is determined using OS-specific rules: for a Windows access violation it is the faulting memory address (the address that was accessed), not the instruction pointer.
- On 32-bit CPUs the crash address is truncated to 32 bits, clearing any sign-extended high bits.
