`single_space_after_construct` adds extra space after comment
## Bug report

### Code snippet that reproduces the problem

```diff
    1) data/src/Persistence/Sql/Query.php (single_space_after_construct)
      ---------- begin diff ----------
--- /__w/data/data/src/Persistence/Sql/Query.php
+++ /__w/data/data/src/Persistence/Sql/Query.php
@@ -816,7 +816,7 @@
         $ret = [];

         if ($this->args['set']) {
-            foreach ($this->args['set'] as [$field/*, $value*/]) {
+            foreach ($this->args['set'] as [$field/*, $value*/ ]) {
                 $field = $this->consume($field, self::ESCAPE_IDENTIFIER);

                 $ret[] = $field;

      ----------- end diff -----------
```

no space should be added around comments as this complicates debugging and it the case above it is even wrong

### Additional contract requirements

- The `single_space_after_construct` fixer must not insert a space between a comment and the closing square bracket of a destructuring assignment. For example, `foreach ($fields as [$field/* comment */])` must be left unchanged.
- This requirement applies specifically to a comment placed immediately before the closing square bracket of a destructuring assignment; it does not extend to comments in other positions.
