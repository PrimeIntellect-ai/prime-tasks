Error.annotate reference numbers are wrong
#### Context

* *node version*:6
* *joi version*:9
* *environment* (node, browser):node
* *used with* (hapi, standalone, ...):standalone
* *any other relevant information*:

#### What are you trying to achieve or the steps to reproduce ?
```
let r = joi.validate({a:{b:3, d:4}, c:5}, {a:{b:joi.string()}}, {allowUnknown: false, abortEarly: false});
console.log(r.error.annotate()).
```
#### Which result you had ?
```
{
  "a": {
    "d" [2]: 4,
    "b" [3]: 3
  },
  "c" [1]: 5
}

[1] "b" must be a string // This talks about "b", which is the third reference
[2] "d" is not allowed  // And so on
[3] "c" is not allowed
```

#### What did you expect ?
```
{
  "a": {
    "d" [2]: 4,
    "b" [3]: 3
  },
  "c" [1]: 5
}

[1] "c" is not allowed
[2] "d" is not allowed
[3] "b" must be a string
```

### Additional contract requirements

- When several errors refer to the same value, the annotation must show their reference numbers as `[3, 2, 1]` when the corresponding error messages are numbered `[1]`, `[2]`, and `[3]`.
