A bug in support.Translations class prevent merge method to work with python 3
This code sample works well in python 2:

    from babel.support import Translations
    translations = Translations.load("path/to/translations", ["en"])
    other_translations = Translations.load("other/path/to/translations", ["en"])
    translations.merge(other_translations)

Switching to python 3 make it to throw an AttributeError ('filter' object has no attribute 'extend') at babel/support.py:590:

    self.files.extend(translations.files)

It turns out that self.files is set at babel/support.py:284:

    [HIDDEN]

[HIDDEN] [HIDDEN], but I'm not sure what side effects it could have:

    [HIDDEN]

### Additional contract requirements

- When translation catalogs are merged, the receiver retains the translated values of messages from both catalogs.
- The receiver aggregates the source filenames from both translations so they are available through its `files` attribute.
- Merging translations must work on Python 3 without failing because the receiver’s `files` collection cannot be extended.
