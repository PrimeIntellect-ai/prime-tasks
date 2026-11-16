`wrap_comments` removes spaces after leading dot
Is this expected?
```diff
❯ cargo fmt --check
Diff in /private/tmp/tmp/src/main.rs at line 1:
 fn main() {
     // f   3    .
     // t   3    .
-    // .   .    3.5
-    // .   .    -4.3
-    // .   .    .
+    // . .    3.5
+    // . .    -4.3
+    // . .    .
 }
```

```
rustfmt 1.6.0-nightly (0e8e857b 2023-07-16)
```
