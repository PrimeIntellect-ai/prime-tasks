""" getting placed at end of comment line instead of its own line
docformatter is resulting in this diff:

```
-    """
-    return a map mapping appliance_ids for a house back to themselves
-    except for multiphase appliances
-    """
+    """return a map mapping appliance_ids for a house back to themselves except
+    for multiphase appliances."""
```

I'm ok with putting the word return immediately after the triple quotes, but shouldn't the final set of triple quotes be on their own line?

### Additional contract requirements

Provide the `--close-quotes-on-newline` command-line option. When enabled, if a one-line docstring wraps onto multiple summary lines, place the closing triple quotes on a line of their own. If the summary does not wrap, keep the closing quotes on the final summary line.
