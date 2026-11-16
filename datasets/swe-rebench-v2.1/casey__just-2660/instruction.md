bug: default and variadic parameter ordering
```
❯ just deploy
error: Parameter `nonce` follows variadic parameter
  ——▶ Justfile:24:15
   │
24 │ deploy  *ARGS nonce="1":
   │               ^^^^^
(py313)
lottery.multiversex on  main [!?] is 📦 v0.0.1 via 🐍 v3.13.1 via 🦀 v1.85.0 via 🅒 py313 on ☁️  (us-east-1)
❯ just deploy
error: Non-default parameter `ARGS` follows default parameter
  ——▶ Justfile:24:19
   │
24 │ deploy nonce="1" *ARGS:
   │                   ^^^^
(py313)
```

The 2nd option is the way to go..
