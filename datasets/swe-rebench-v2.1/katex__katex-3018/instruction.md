Error when rendering empty matrix
**Describe the bug:**
KaTeX errors when asked to render an empty matrix.

**To Reproduce:**
Attempt to render
```
\begin{bmatrix}
\end{bmatrix}
```
We get the error
```
o.body[0] is undefined
```

**Environment (please complete the following information):**
 - KaTeX Version: 0.13.10
 - Device: Desktop
 - OS: Linux
 - Browser: Firefox
 - Version: 88.0.1

**Additional context:**
Demo link:

https://katex.org/?data=%7B%22displayMode%22%3Atrue%2C%22leqno%22%3Afalse%2C%22fleqn%22%3Afalse%2C%22throwOnError%22%3Atrue%2C%22errorColor%22%3A%22%23cc0000%22%2C%22strict%22%3A%22warn%22%2C%22output%22%3A%22htmlAndMathml%22%2C%22trust%22%3Afalse%2C%22macros%22%3A%7B%22%5C%5Cf%22%3A%22%231f(%232)%22%7D%2C%22code%22%3A%22%5C%5Cbegin%7Bbmatrix%7D%5Cn%5C%5Cend%7Bbmatrix%7D%22%7D
