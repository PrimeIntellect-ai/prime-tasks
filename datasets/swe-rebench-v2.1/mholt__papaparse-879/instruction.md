Multi-character delimiter and quoted fields
Recently a user reported an issue to me that multi-character delimiter does not work with quoted fields, e.g.

```
a, b, "c, e", d
```
delimiter: `, ` (comma and a single whitespace)

I tried this on the current demo version (on the website):
```js
Papa.parse('a, b, "c, e", d', {delimiter: ', '})
```
which gives:
```js
'a', 'b', 'c, e", d'
```
expected

```js
'a', 'b', 'c, e', 'd'
```

I also noticed that in the documentation there is always written `delimiting character` but actually multi-character strings are supported (from what I can see in the code and tests).


I think the issue is somewhere around this line: https://github.com/mholt/PapaParse/blob/master/papaparse.js#L1558

[HIDDEN]

A test could look like this:

```js
{
  description: "Multi-character delimiter (length 2) with quoted field",
  input: 'a, b, "c, e", d',
  config: { delimiter: ", " },
  notes: "The quotes must be immediately adjacent to the delimiter to indicate a quoted field",
  expected: {
    data: [['a', 'b', 'c, e', 'd']],
    errors: []
  }
}
```

### Additional contract requirements

- When a closing quote is followed by the configured multi-character delimiter, parsing must recognize the delimiter and continue with the next field.
