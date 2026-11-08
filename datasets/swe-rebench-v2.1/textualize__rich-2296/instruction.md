[BUG] Text wrapping edge case
Discovered a possible edge case with text wrapping, probably connected to when a "word" is greater than the available width.

Consider the following:

```python
console.print("Hello, World...123 ", width=10)
```

This produces:

```
Hello, Wor
ld...123
```

I think this occurs because "World...123" doesn't fit in to 10 characters, so folds on to the next line.

I would expect there to be an additional new line after the Hello, like this:

```
Hello,
World...12
3
```
