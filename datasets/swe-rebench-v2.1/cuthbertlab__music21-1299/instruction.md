Make cautionaryPitchClass work inside a single chord
**Motivation**
`cautionaryPitchClass=True` could make the following example print an F-natural at the bottom.

```python
>>> c = chord.Chord('F4 F#5')
>>> c.show()
```
Current:
![Screen Shot 2022-02-18 at 2 02 42 PM](https://user-images.githubusercontent.com/38668450/154745938-80a68f1e-09fe-4b72-bdd7-8dd9a722a4d7.png)


**Feature summary**
I think this could be on by default, even in a diatonic context. Or we can just do this in keyless contexts.

**Proposed implementation**
Similar to #1190 , maybe handle in tandem

**Intent**
<!-- Please check one or more boxes -->

[x] I plan on implementing this myself
[ ] I am willing to pay to have this feature added.
[ ] I am starting a discussion with the hope that community members will volunteer their time to create this. I understand that individuals work on features of interest to them and that this feature may never be implemented.
