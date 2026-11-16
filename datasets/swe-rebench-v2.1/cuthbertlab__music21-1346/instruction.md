makeTies in makeNotation failing with end split
<!-- Version of music21:  print(music21.__version__) -->
**music21 version**

`8.0alpha master`   <!-- replace with actual version -->


**Problem summary**
<!-- Briefly: what undesired thing happens when what action is taken? -->

makeTies is supposed to be able to create new measures to deal w/ long notes extending beyond the final measure, and works fine when called separately but fails when called in makeNotation

**Steps to reproduce**

```
p = stream.Part()
m = stream.Measure(number=1)
m.append(meter.TimeSignature('4/4'))
m.append(note.Note(type='breve'))
p.append(m)
p.makeNotation().show('text', addEndTimes=True)
p.makeTies().show('text', addEndTimes=True)
```

**Expected vs. actual behavior**
<!-- Consider annotating the output produced by a function -->
*Expected*: both show 'text' will have two measures.

*Actual*:
```
>>> p.makeNotation().show('text', addEndTimes=True)
{0.0 - 4.0} <music21.stream.Measure 1 offset=0.0>
    {0.0 - 0.0} <music21.meter.TimeSignature 4/4>
    {0.0 - 4.0} <music21.note.Note C>

>>> p.makeTies().show('text', addEndTimes=True)
{0.0 - 4.0} <music21.stream.Measure 1 offset=0.0>
    {0.0 - 0.0} <music21.meter.TimeSignature 4/4>
    {0.0 - 4.0} <music21.note.Note C>
{4.0 - 8.0} <music21.stream.Measure 2 offset=4.0>
    {0.0 - 4.0} <music21.note.Note C>
```


**More information**
<!-- If relevant: OS, suggested fix, attempted workarounds -->
OS: macOS

<!-- Note: only Mac and Windows are directly supported by music21 staff.
     Bug reports that are specific to other OSes w/o a PR will be closed
     unless the reporter is willing to contribute a fix.
 -->
