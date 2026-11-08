@ binding reformatted strangely on rustfmt from rustc 1.41.0-beta.4
The following line is formatting differently and in an undesirable way with rustfmt from rustc beta (1.41.0-beta.4):

https://github.com/yeslogic/allsorts/blob/c78fb470ca2a575570543918cfbf15422b0377b2/tests/woff2.rs#L236

The diff looks like this:

```diff
Diff in /home/travis/build/yeslogic/allsorts/tests/woff2.rs at line 233:
             .iter()
             .map(|glyph| match glyph {
                 GlyfRecord::Parsed(
-                    found @ Glyph {
+                    found
+                    @
+                    Glyph {
                         data: GlyphData::Composite { .. },
                         ..
                     },
```
