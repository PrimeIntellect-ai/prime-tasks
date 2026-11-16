tabs are not preserved in string literals
Tabs within strings are converted to two spaces. Similar code formatters like rubocop and Prettier preserve tabs within strings, making this behavior surprising.

I noticed this while running nixpkgs-fmt on a NixOS configuration file with rules for /etc/exports. The change doesn't affect the meaning of the file, but might for other file types (TSV?).

## Input
```nix
{
  simpleStringLiteral = "col	col";

  multilineStringLiteral = ''
    col	col	col
  '';
}
```

## Output
```nix
--- Input
+++ Output
@@ -1,7 +1,7 @@
 {
-  simpleStringLiteral = "col	col";
+  simpleStringLiteral = "col  col";

   multilineStringLiteral = ''
-    col	col	col
+    col  col  col
   '';
 }
```

## Desired output

```nix
{
  simpleStringLiteral = "col	col";

  multilineStringLiteral = ''
    col	col	col
  '';
}
```
