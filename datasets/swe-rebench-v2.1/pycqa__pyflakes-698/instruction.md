assignment expression in comprehension should target outer scope
Please consider the following example, which finds the first String in a list that contains the Substring "OH":

```
list = ["STEVE", "JOHN", "YOANN"]
pattern = re.compile(".*%s.*" % "OH")
word = ""

if any((match := pattern.match(item)) for item in list):
    word = match.group(0)
print(word)
```

The code works as intended and outputs "JOHN", but I am getting the following warning from flake8 at
the line ```word = match.group(0):```

```
F821 -- undefined name 'match'
```

I made a post on [StackOverflow](https://stackoverflow.com/questions/67547135/why-does-flake8-give-the-warning-f821-undefined-name-match-when-using-match), where Anthony Sottile recommended me to post the issue here. I'm using flake8 3.9.2 (mccabe: 0.6.1, pycodestyle: 2.7.0, pyflakes: 2.3.1) CPython 3.9.5 on Windows.

### Additional contract requirements

A name assigned with an assignment expression inside a comprehension is bound in the containing scope, so a later reference there is not reported as undefined. This applies to set and dictionary comprehensions as well as other comprehension forms.
