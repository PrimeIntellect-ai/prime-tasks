stripTies() exception with chord symbols in v7.3.3
<!-- Version of music21:  print(music21.__version__) -->
**music21 version**

Issue is present on `7.3.3`, but not on `'6.7.1'`. Looks like a regression.

**Problem summary**

When calling `.stripTies()` on a score imported from MusicXML, an exception occurs when a tie over a barline has a chord symbol on the "stop" note. E.g. for this score

![image](https://user-images.githubusercontent.com/369527/167020306-c826a996-34e7-4052-a36e-5dc054c4b3cb.png)

calling `x.stripTies()` fails with:

```
>>> x.stripTies()
 Traceback (most recent call last):
   File "<stdin>", line 1, in <module>
   File "/Users/xavriley/opt/anaconda3/envs/qparse/lib/python3.9/site-packages/music21/stream/base.py", line 7126, in stripTies
     p.stripTies(inPlace=True, matchByPitch=matchByPitch)
   File "/Users/xavriley/opt/anaconda3/envs/qparse/lib/python3.9/site-packages/music21/stream/base.py", line 7312, in stripTies
     raise StreamException('aggregated ties have a zero duration sum')
 music21.exceptions21.StreamException: aggregated ties have a zero duration sum
```

Removing the chord symbol in the second bar ("Bb7") allows `stripTies()` to succeed.

**Steps to reproduce**

I did try to reproduce this using tiny notation but as far as I can tell, it only happens with a score from a MusicXML source.

A minimal XML example is available here: https://www.dropbox.com/s/xce206n23by2a3m/stripTiesBug.xml?dl=0. Loading it with

```
from music21 import *
x = converter.parse("/path/to/stripTiesBug.xml")
x.stripTies()
```

is enough to reproduce the issue.

Strangely, the following tinyNotation produces the same stream but *does not* raise an exception.

```
myStream1 = m21.converter.parse('tinynotation: 4/4 C.4 C8 F.4 B-8~ | B-8 B-8 D4 G4 F4')
myStream1.measures(0, None)[0].insert(0, m21.harmony.ChordSymbol('C7'))
myStream1.measures(0, None)[0].insert(2, m21.harmony.ChordSymbol('F7'))
myStream1.measures(0, None)[1].insert(0, m21.harmony.ChordSymbol('B-7'))
myStream1.stripTies()
```

**Expected vs. actual behavior**

`stripTies()` should work when chord symbols are present.

**More information**

As a workaround, removing the chord symbols seems to allow `stripTies()` to work e.g.

```
for c in x.recurse().getElementsByClass(m21.harmony.ChordSymbol):
    x.remove(c, recurse=True)

x.stripTies() # succeeds
```
