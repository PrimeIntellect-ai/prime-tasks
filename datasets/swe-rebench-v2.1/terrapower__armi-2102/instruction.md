Weird behavior with case clone, copied inputs, and setting expecting a list of files
I saw some weird behavior recently that I'm going to try to explain as best I could.

We have an input file that has a setting that expects list of files. When we have armi clone the case, it
1. removed the list behavior on the setting, and
2. mangled the setting contents when writing the new settings file.

Initially, we had something like

```yaml
specialFiles:
  - first_file.txt
```

And following the clone, we got
```yaml
specialFiles:
  - f
  - i
  - r
  - s
  - t
  - _
  - f
  - i
  - l
  - e
  - .
  - t
  - x
  - t
```

After some inspection, I found this line in `copyInterfaceInputs`, the function responsible for moving ancillary files found in the input to the location of the cloned suite
[HIDDEN]

The `first_file.txt` was correctly moved. But this line set the `specialFiles` setting not to be a list of a single element, but a string with the file. Then, logic that writes the new settings file still sees an iterable of strings for `specialFiles` and writes out each character as if it were a new setting.

This caused the run to crash because the code that works with `specialFiles` cannot access the file `f`.
