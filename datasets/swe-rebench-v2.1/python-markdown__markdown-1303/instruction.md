stand-alone * or _ lead to incorrect results
A text with several stand-alone underscores is not converted correctly.

**input**
```
**_ _ _ N _ _ _ _ _ _ _ R S _ _ N _**
```

**output**
```
 <p><strong><em> _ </em> N _ <em> _ </em> _ <em> _ R S _ </em> N _</strong></p>
```

**expected**
```
<p><strong>_ _ _ N _ _ _ _ _ _ _ R S _ _ N _</strong></p>
```

It seems that underscores with the surrounding spaces are replaced by the `placeholder`.
In the original on [https://daringfireball.net/projects/markdown/dingus](https://daringfireball.net/projects/markdown/dingus) it is converted correctly.
