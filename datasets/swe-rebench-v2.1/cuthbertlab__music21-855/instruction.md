Durationless element can get inserted twice; missing safeguard in coreGuardBeforeAddElement
**music21 version**

7


**Problem summary**
`makeMeasures` can insert the same element in a stream twice when the element coincides with the end of the stream. We made this change in #592 but didn't notice that it was inserting the identical element from the flat source into the newly created measure.


**Steps to reproduce**

```
>>> p = stream.Part()
>>> p.insert(4, meter.TimeSignature())
>>> p.makeMeasures(inPlace=True)
>>> for el in p.recurse():
...   print(el, id(el))
```

**Expected vs. actual behavior**
<music21.stream.Measure 1 offset=0.0> 4465547536
<music21.clef.TrebleClef> 4465548496
<music21.meter.TimeSignature 4/4> 4465547392
<music21.meter.TimeSignature 4/4> **4465410544**
<music21.bar.Barline type=final> 4465692736
<music21.meter.TimeSignature 4/4> **4465410544**

**More information**
This came up putting together the make measures patch for MIDI import, since the conductor track will only extend as far as the last element (which will be durationless time signature or key signature), and if we make measures, we choke here.

Making a deep copy before inserting might work, but in addition, I would think a safeguard is missing here? It wasn't obvious to me since `storeAtEnd` runs `coreGuardBeforeAddElement`.
