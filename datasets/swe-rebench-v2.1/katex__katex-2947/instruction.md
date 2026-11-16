Empty top-level environment crashes
**Describe the bug:**
Empty `align` environments (and `equation` and probably other top-level environments) cause the following JavaScript error:
```
Cannot read property 'shift' of undefined
```

**To Reproduce:**
Steps to reproduce the behavior:
1. Go to https://katex.org
2. Enter
   ```latex
   \begin{align}
   \end{align}
   ```

[Direct link](https://katex.org/?data=%7B%22displayMode%22%3Atrue%2C%22leqno%22%3Afalse%2C%22fleqn%22%3Afalse%2C%22throwOnError%22%3Atrue%2C%22errorColor%22%3A%22%23cc0000%22%2C%22strict%22%3A%22warn%22%2C%22output%22%3A%22htmlAndMathml%22%2C%22trust%22%3Afalse%2C%22macros%22%3A%7B%7D%2C%22code%22%3A%22%5C%5Cbegin%7Balign%7D%5Cn%5C%5Cend%7Balign%7D%22%7D)

**Expected behavior:**
I expect an empty math expression.

Curiously, `\begin{aligned} \end{aligned}` works fine.

**Screenshots:**
![image](https://user-images.githubusercontent.com/2218736/115302167-210e0080-a130-11eb-9e34-33153b138dbd.png)
