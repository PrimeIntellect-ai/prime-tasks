Bug Capitalize Headings: bug with accented letters
Hi ! Here is a but with  the "Capitalize Headings" fonction.

## Describe the Bug
When Capitalize Headings is enabled, and a title begins with an accented letter, the first two letters of the title will be capitalized instead of just the first letter.



## How to Reproduce

Steps to reproduce the behavior:

1. Just write a title starting with an accented letter
2. lint the file with Capitalize Headings a/ enabled ; b/ Style set to "First letter"


## Unexpected Behavior

E.g
```
## état
```
will be replaced by
```
## ÉTat
```
and
```
## équilibre
```
will be replaced by
```
## ÉQuilibre
```

## Expected Behavior
```
## état
```
should be replaced by
```
## État
```
and
```
## équilibre
```
will be replaced by
```
## Équilibre
```


Thanks for your work !
Michaël

### Additional contract requirements

- When the style is “Title Case,” accented letters are treated as letters for capitalization: `## état` becomes `## État`, and `## this état` becomes `## This État`.
- For the “First letter” style, capitalization changes only the letter casing of the heading text; it does not add or remove any other characters, so trailing whitespace in the heading is preserved.
