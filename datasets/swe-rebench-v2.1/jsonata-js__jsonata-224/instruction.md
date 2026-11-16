Defining functions for use with $match etc.
As discussed in [this thread](https://github.com/jsonata-js/jsonata/issues/177), the functions `$match`, `$contains`, `$split` and `$replace` all take a function that returns the matches of a particular pattern in a string. Regular expressions are one type of matching function but users can provide their own. I tried this out (to check that jsonata-go is doing the right thing) and found it quite tricky to get working.

I expected this expression to return one match:

```
(
    $f := function($arg) {
        {
            "match": "ab",
            "start": 0,
            "end": 2,
            "groups": [],
            "next": function() { nothing }
        }
    };

    $match("abracadabra", $f)
)
```

But instead it returned an error: `t is not a function`. So I re-ran the expression in the JavaScript console and got the slightly longer error: `Uncaught TypeError: regex is not a function` (`regex` is the name of the argument to `functionMatch`).

Ok, so lambdas can't be used as matching functions. Not a problem. I rewrote the function in JavaScript, added it to JSONata with `registerFunction`, and used that as the second argument to `$match`. Same error!

[HIDDEN] I tried using `assign` instead of `registerFunction` and that fixed the problem.

I have one observation and one question about this:

1. Functions added via `registerFunction` should work. It doesn't make sense for the same matching function to be valid when bound with `assign` and invalid when bound with `registerFunction`.

2. Is there a reason why lambdas can't be used as matching functions or is it just an oversight?

p.s. I only tried `$match` and `$contains` but I can see from the code that `$split` and `$replace` will have the same issues. They all call the matching function directly.

### Additional contract requirements

- A JSONata lambda or a JavaScript function exposed through `registerFunction` can be used as a matching function with `$match`, `$contains`, `$split`, and `$replace`. This includes a matcher function returned by a registered function.
- A matching function is called with the input string and an optional starting offset. It returns either `undefined` when there are no further matches, or an object containing `match`, `start`, `end`, `groups`, and `next`; `next` returns the next match object or `undefined`.
