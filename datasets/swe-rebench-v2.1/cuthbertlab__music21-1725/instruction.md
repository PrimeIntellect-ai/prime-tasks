Stem styles aren't exported unless stemDirection is explicit
**music21 version**
dev

**Problem summary**
Stem styles (e.g. colors) aren't exported if the stem direction is unspecified.

**Steps to reproduce**

```py
s = converter.parse('tinyNotation: 2/4 c2')
s.recurse().notes.first().style.stemStyle = style.Style()
s.recurse().notes.first().style.stemStyle.color = 'red'
s.write()
```

**Expected vs. actual behavior**
.write() doesn't produce a `<stem>` element. Expected:

```xml
<stem color="#FF0000">up</stem>
```
