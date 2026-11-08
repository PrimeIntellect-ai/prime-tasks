Edge case for `Compound.get_boundingbox()`
**Bug summary**

I bumped into an edge case where `Compound.get_boundingbox()` might return an unexpected error.

**Code to reproduce the behavior**
```python3
import mbuild as mb
h1 =  mb.Compound()
h1.pos = [-0.07590747,  0.00182889,  0.00211742]
h2 = mb.Compound()
h2.pos = [0.07590747,  -0.00182889,  -0.00211742]
container = mb.Compound([h1, h2])

container.get_boundingbox()
```

**Software versions**

- Which version of mBuild are you using? (`python -c "import mbuild as mb; print(mb.__version__)"`) 0.13.1
- Which version of Python (`python --version`)? 3.8
- Which operating system? MacOS

### Additional contract requirements

`Compound.get_boundingbox` accepts an optional `pad_box` argument that defaults to `None` and returns an `mb.Box`.

- A single numeric value (`int`, `float`, or numeric string) is applied equally to all three box lengths.
- A sequence (list or tuple) of length 1 is applied equally to all three box lengths.
- A sequence (list or tuple) of length 3 gives the individual padding for the a, b and c box lengths.
- Padding values are converted to `float`; a padding value that cannot be converted to `float` raises `TypeError`.
- Any other `pad_box` value, including a set, a mapping, or a sequence whose length is not 1 or 3, raises `TypeError`.
- When `pad_box` is provided, the returned box lengths are the compound's bounding-box lengths increased by the corresponding padding amounts.
- When the box vectors are collinear, `MBuildError` is raised with a message containing `The vectors to define the box are co-linear,`.
