Short anonymous hyperlink references get messed up
docformatter doesn't correctly recognize the short form of anonymous hyperlink references (`__ URI`) as a special block, and merges them into the preceding paragraph:

```diff
     """[...]

     This graphics format generates terminal escape codes that transfer
-    PNG data to a TTY using the `kitty graphics protocol`__.
-
-    __ https://sw.kovidgoyal.net/kitty/graphics-protocol/
+    PNG data to a TTY using the `kitty graphics protocol
+    `__. __ https://sw.kovidgoyal.net/kitty/graphics-protocol/
     """
```

This breaks the reST, and makes Sphinx unable to correctly process the reference.

Note that this only affects this shorter form; the long form (`.. __: URI`) is unaffected. The following variation (correctly) remains unchanged by docformatter:

```
    """[...]

    This graphics format generates terminal escape codes that transfer
    PNG data to a TTY using the `kitty graphics protocol`__.

    .. __: https://sw.kovidgoyal.net/kitty/graphics-protocol/
    """
```

Bisecting brought up 7898b69f49d43a0a0ac63a8e92afac974a478383 as the first "bad" commit, which is exactly v1.6.0. The earlier 917fed92248d1fb91a1f4da61b5aaaec7367fe23 also changed the output already, but in a slightly different way and it was probably rewritten anyways.
