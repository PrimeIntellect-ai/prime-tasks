Using splitByQuarterLengths on stream causes an AttributeError
**music21 version**

`9.1.0`


**Problem summary**
Using splitByQuarterLengths on a stream object causes the following error:
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/acerola/.local/lib/python3.10/site-packages/music21/base.py", line 3364, in splitByQuarterLengths
    spannerList.extend(st.spannerList)
AttributeError: 'tuple' object has no attribute 'spannerList'
```


**Steps to reproduce**

```
>>> from music21 import stream, note
>>> stream.Measure([note.Note(quarterLength=8)]).splitByQuarterLengths([4, 4])
```

**Expected vs. actual behavior**
Expected: the function finishes executing and the stream is properly split.
Actual: AttributeError

**More information**
[HIDDEN]
