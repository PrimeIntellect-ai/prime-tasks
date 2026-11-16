Markdown variables consume too many characters if parentheses are nested with whitespace before final )
Not sure what is causing this issue, but it is a bug of some sort.

Some combination of links and parentheses inside tables merges cells together, sometimes splitting words.

the following code will work as a demonstration:
```
|  title 1  | title 2 | title 3 | title 4|
|-----------|---------|---------|--------|
|[foo](bar) |  Ipsum  |    )    |   )    |
```
results in this:
![image](https://github.com/naturalcrit/homebrewery/assets/91662974/29122643-a802-4f1d-8bf5-ab4d49917801)
