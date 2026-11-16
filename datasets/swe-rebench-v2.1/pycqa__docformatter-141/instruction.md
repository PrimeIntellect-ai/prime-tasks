Bugs in link handling in 1.5.1
I've run into a couple issues related to formatting links in 1.5.1.

1. Error with short link

To reproduce, create a file `tmp.py` containing:
```
"""
Test test.

See `the link <https://www.link.com>`_ for more details.
"""
```
Running `docformatter tmp.py` gives an error
```
   ...
  File ".../lib/python3.9/site-packages/docformatter/syntax.py", line 272, in wrap_description
    text = do_preserve_links(text, indentation, wrap_length)
  File ".../lib/python3.9/site-packages/docformatter/syntax.py", line 82, in do_preserve_links
    url = url + lines[url_idx + 1].strip()
IndexError: list index out of range
```

2. Long links that get broken across lines also remove spaces from the text following the link

```
"""
Test test.

See `the link <https://www.link.com/a/long/link/that/causes/line/break>`_ for more details.
"""
```
Running `docformatter tmp.py` produces the output
```
--- before/tmp.py
+++ after/tmp.py
@@ -1,5 +1,6 @@
+"""Test test.
+
+See `the link
+
+<https://www.link.com/a/long/link/that/causes/line/break>`_ for moredetails.
 """
-Test test.
-
-See `the link <https://www.link.com/a/long/link/that/causes/line/break>`_ for more details.
-"""
```
Note that the space has been removed between "more" and "details".
