`rustfmt` is not idempotent and not consistent
When formatting the following code,

```rust
mod test {
    extern "C" {fn test();}
}
```
The first diff suggested by `rustfmt` is
```diff
-    extern "C" {fn test();}
+    extern "C" {
+        fn test();    }
```
After running this formatting, the next suggestion is
```diff
-        fn test();    }
+        fn test();
+    }
```
The final result seems to be correct, but should most likely be applied at once, not in two steps.

Additionally, removing the `mod` block causes the changes to look like this:
```rust
extern "C" {fn test();}
```
```diff
-extern "C" {fn test();}
+extern "C" {
+    fn test();}
```
This change _is_ idempotent, but I would expect the closing `}` to be moved to the next line (which is what happens if a whitespace is put in between the final `;` and `}`).
