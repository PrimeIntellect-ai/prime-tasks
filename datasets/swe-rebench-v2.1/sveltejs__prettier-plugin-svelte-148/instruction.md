Broken change for div with `class`
Testing v1.3.0 with previous formatting on v1.2.1 resulted in this change:

```
-    <div class="met-ex metropolis02">
-      Growth <b>&</b> Usage
+    <divclass="met-ex metropolis02">
+      Growth
+      <b>&</b>
+      Usage
```
