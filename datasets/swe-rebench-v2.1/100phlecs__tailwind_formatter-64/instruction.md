Formatter breaks special class attribute: `[scrollbar-gutter: stable]`
The space before the `stable` keyword is mandatory
```
[...]layouts/root.html.heex

  1   1  |<!DOCTYPE html>
  2     -|<html lang="en" class="[scrollbar-gutter: stable]">
      2 +|<html lang="en" class="stable] :[scrollbar-gutter">
  3   3  |  <head>
  4   4  |    <meta charset="utf-8" />
         |
```
