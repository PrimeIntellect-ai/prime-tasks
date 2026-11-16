Option --sort-output only uses msgid to sort translations
When you have several identical `msgid` with different `msgctxt`, using `--sort-ouput` will only sort the translations according to `msgid` leading to a random order in the output.

This leads to useless diff in the VCS:

```
-msgctxt "payment mode"
+msgctxt "subscription"
 msgid "Expired"
 msgstr "Expired"

-msgctxt "subscription"
+msgctxt "payment mode"
 msgid "Expired"
 msgstr "Expired"
```

I'd like Babel to also use `msgctxt` to sort the output.
