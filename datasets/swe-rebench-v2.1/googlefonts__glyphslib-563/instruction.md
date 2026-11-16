can't roundtrip glyphs2ufo and ufo2glyphs for a particular Rubik-Italic.glyphs file
When I run glyphs2ufo on this file, and then run ufo2glyphs again without changing anything I get an error (see below). Usually this process works without issue, but just one this one file I have a problem. For whatever reason this only happens on the Italic and not on the Roman. I've hit this error while working on making variable font versions of the family for Google Fonts and Dave and Marc said I should report it here, since it looks like a bug. Thanks!

Full traceback is:
~~~
Traceback (most recent call last):
  File "/Users/cjdunn/env_gtools/bin/ufo2glyphs", line 10, in <module>
    sys.exit(_ufo2glyphs_entry_point())
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/cli.py", line 268, in _ufo2glyphs_entry_point
    return main(args)
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/cli.py", line 169, in main
    return options.func(options)
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/cli.py", line 244, in ufo2glyphs
    object_to_read, minimize_ufo_diffs=options.no_preserve_glyphsapp_metadata
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/__init__.py", line 139, in to_glyphs
    return builder.font
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/builders.py", line 654, in font
    self.to_glyphs_features()
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/features.py", line 274, in to_glyphs_features
    glyphs_module=self.glyphs_module,
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/features.py", line 287, in _to_glyphs_features
    document = FeaDocument(features_text, glyph_names)
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/features.py", line 342, in __init__
    self._build_end_locations()
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/features.py", line 372, in _build_end_locations
    self._build_end_locations_rec(self._doc)
  File "/Users/cjdunn/env_gtools/lib/python3.7/site-packages/glyphsLib/builder/features.py", line 396, in _build_end_locations_rec
[HIDDEN]
IndexError: list index out of range

~~~

Here's the file:
[Rubik_Italic.glyphs.zip](https://github.com/googlefonts/glyphsLib/files/3799060/Rubik_Italic.glyphs.zip)
