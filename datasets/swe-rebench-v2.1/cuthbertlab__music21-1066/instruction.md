Unexpected mixed stem directions from `setStemDirectionForBeamGroups()`
**music21 version**

dev; likely an issue since 6.7

**Problem summary**
`setStemDirectionOneGroup()`, a helper routine for `setStemDirectionForBeamGroups()` treats a mixture of "up" and "unspecified" stem directions as "consistent" for the purposes of how careful to be about observing the kwarg `overrideConsistentStemDirections`. Then, when unspecified stem directions are encountered during a scan, there is no look-back to fix the earlier directions, leading to mismatch:


**Steps to reproduce**

```
>>> s = stream.Stream()
>>> s.insert(clef.TrebleClef())
>>> n1 = note.Note('B4')
>>> n2 = note.Note('B3')
>>> n1.stemDirection = 'down'
>>> n2.stemDirection
'unspecified'
>>> s.append(n1)
>>> s.append(n2)
>>> stream.makeNotation.setStemDirectionOneGroup([n1, n2])
>>> n1.stemDirection  # expect 'up' to match n2
'down'
>>> n2.stemDirection
'up'
>>> s.show()
```

**Expected vs. actual behavior**
![Screen Shot 2021-07-20 at 7 36 52 PM](https://user-images.githubusercontent.com/38668450/126408341-9931c8c7-9baf-48dc-b9c2-a52f9dbc6c37.png)

**More information**
[HIDDEN]

### Additional contract requirements

- When stem directions are set for a beam group, a group that contains a note whose stem direction is "unspecified" must not be treated as already having consistent stem directions, even if its other notes share one direction. For the reported case (a two-note group in treble clef on B4 and B3, where the first note is set to "down" and the second is "unspecified"), after the group's stem directions are set both notes must have stem direction "up".
