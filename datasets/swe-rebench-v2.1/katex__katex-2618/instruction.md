No character metrics for Armenian letters
**Describe the bug:**
Discovered by Khan Academy Armenian translators. When `\cancel{\text{g}}` works fine, but putting in a character from armenian alphabet (outside of KaTeX fonts) inside the `\text` breaks it.

https://katex.org/?data=%7B%22displayMode%22%3Atrue%2C%22leqno%22%3Afalse%2C%22fleqn%22%3Afalse%2C%22throwOnError%22%3Atrue%2C%22errorColor%22%3A%22%23cc0000%22%2C%22strict%22%3A%22warn%22%2C%22output%22%3A%22htmlAndMathml%22%2C%22trust%22%3Afalse%2C%22macros%22%3A%7B%22%5C%5Cf%22%3A%22%231f(%232)%22%7D%2C%22code%22%3A%22%5C%5Ccancel%7B%5C%5Ctext%7B%D5%A3%7D%7D%22%7D

However, this works `\cancel{\text{aգ}}`, suggesting that the issue is caused by the lack of vertical metrics for the argument.
As a workaround, one could do something like `\cancel{\text{\vphantom{a}գ}}`, but that's not a viable solution for our translators because changes to LaTeX markup get rejected by our linter.

**To Reproduce:**
Link to katex.org

https://katex.org/?data=%7B%22displayMode%22%3Atrue%2C%22leqno%22%3Afalse%2C%22fleqn%22%3Afalse%2C%22throwOnError%22%3Atrue%2C%22errorColor%22%3A%22%23cc0000%22%2C%22strict%22%3A%22warn%22%2C%22output%22%3A%22htmlAndMathml%22%2C%22trust%22%3Afalse%2C%22macros%22%3A%7B%22%5C%5Cf%22%3A%22%231f(%232)%22%7D%2C%22code%22%3A%22%5C%5Ccancel%7B%5C%5Ctext%7B%D5%A3%7D%7D%22%7D

**Expected behavior:**
I guess `\cancel` should use some reasonable height default for characters without vertical metrics.

**Screenshots:**

![obrazek](https://user-images.githubusercontent.com/9539441/97458416-f5594d00-193a-11eb-82fb-2a02f6f582f1.png)


**Environment (please complete the following information):**
 - KaTeX Version: version on katex.org
 - Device: Laptop
 - OS: Linux
 - Browser: latest Firefox, latest Chrome
