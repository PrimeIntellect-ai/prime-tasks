Rustfmt loses visibility on some trait items and impl items
As of current master, rustfmt applies the following incorrect diff to this valid Rust code.

```diff
 #[cfg(any())]
 trait Visible {
-    pub const C: i32;
+    const C: i32;
     pub type T;
-    pub fn f();
+    fn f();
-    pub fn g() {}
+    fn g() {}
 }

 #[cfg(any())]
 impl Visible for Bar {
     pub const C: i32;
     pub type T;
-    pub fn f();
+    fn f();
     pub fn g() {}
 }
```

To reproduce: `cargo run --bin rustfmt repro.rs`
