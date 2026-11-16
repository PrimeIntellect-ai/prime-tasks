GuitarPro file cannot be parsed in 6.7.0 -- spanner contains same element twice
**music21 version**

`6.7.0`


**Problem summary**
The GuitarPro file provided in a list message about grace notes and lyrics can't be parsed after a regression in 01597856f0ad7e4f113c05aab27706625aed82f8 (feature using templates instead of deepcopies for joinable groups) when serializing fails. Workaround is to use `storePickle=False` so that a pickle isn't written.

**Steps to reproduce**

[frag.xml.zip](https://github.com/cuthbertLab/music21/files/6258453/frag.xml.zip)

```
>>> converter.parse('frag.xml')
converter: Loading original version
converter: Freezing Pickle
Traceback (most recent call last):
  File "/Users/jwalls/music21/music21/sites.py", line 923, in remove
    del self.siteDict[siteId]
KeyError: 4963930560

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/jwalls/music21/music21/converter/__init__.py", line 1167, in parse
    return parseFile(valueStr, number=number, format=m21Format,
  File "/Users/jwalls/music21/music21/converter/__init__.py", line 1027, in parseFile
    v.parseFile(fp, number=number, format=format, forceSource=forceSource, **keywords)
  File "/Users/jwalls/music21/music21/converter/__init__.py", line 572, in parseFile
    sf.write(fp=fpPickle, zipType='zlib')
  File "/Users/jwalls/music21/music21/freezeThaw.py", line 654, in write
    storage = self.packStream(self.stream)
  File "/Users/jwalls/music21/music21/freezeThaw.py", line 242, in packStream
    self.setupSerializationScaffold(streamObj)
  File "/Users/jwalls/music21/music21/freezeThaw.py", line 295, in setupSerializationScaffold
    subSF.setupSerializationScaffold()
  File "/Users/jwalls/music21/music21/freezeThaw.py", line 302, in setupSerializationScaffold
    self.setupStoredElementOffsetTuples(streamObj)
  File "/Users/jwalls/music21/music21/freezeThaw.py", line 466, in setupStoredElementOffsetTuples
    e.sites.remove(streamObj)
  File "/Users/jwalls/music21/music21/sites.py", line 927, in remove
    raise SitesException(
music21.sites.SitesException: an entry for this object (<music21.stream.SpannerStorage 0x127df91c0>) is not stored in this Sites object
```

**More information**
At a glance, it looks like after 01597856f0ad7e4f113c05aab27706625aed82f8 there are some missing spanners in the lower part. They're gathered on musicxml export but not when serializing or getting a text dump from `.show('text')`, so that may have been how we missed this.  Probably just need to gather missing spanners again before serializing.

### Additional contract requirements

- After `stripTies()` on the tested stream, each of the first two spanners in the resulting stream contains exactly one element.
