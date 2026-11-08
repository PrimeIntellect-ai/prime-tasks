webpplEval doesn't work in inference
I know webpplEval isn't technically documented, but there's a [probmods example](https://probmods.org/learning-as-conditional-inference.html#example-inferring-an-arithmetic-expression) that needs something like `eval` to build functions from strings and I was playing around with it anyway! It works just fine outside of an `Infer` statement, but seems to interfere with inference:

```
var foo = Infer({method: 'enumerate'}, function() {
  var int = randomInteger(10);
  var bar = webpplEval('3 +' + int);
  print(bar) // correctly evaluates
  condition(bar == 5);
  return int;
});

foo
```

throws

```
webpplEval error:
Error: factor allowed only inside inference.
```

and if you remove the condition statement, you get

```
webpplEval error:
TypeError: t is not a function
```

The main issue here is probably deciding on the status of `webpplEval` in the language: is it a header function we want to work everywhere (in which case we might want to add it to the docs once fixed up), is it just not intended to work inside inference (in which case we might want to mention that in the docs), or is it something we don't want to expose at all?

### Additional contract requirements

The intended status of `webpplEval` is that it is a header function that works
everywhere, including inside inference. In particular, calling `webpplEval` with
a string of webppl code inside an `Infer`/`Enumerate` query must evaluate that
code and return its value without disturbing the enclosing inference: the query
must still run to completion and produce its support. For example,
`webpplEval('1+1')` must evaluate to `2`, and
`Enumerate(function() { return webpplEval('1+1'); }).support()` must evaluate to
`[2]`.
