[Bug] Incorrect behaviour with following function invocation
Fluent Syntax book shows the following snippet.
```fluent
liked-count = { $num ->
        [0]     No likes yet.
        [one]   One person liked your message
       *[other] { $num } people liked your message
    }

liked-count2 = { NUMBER($num) ->
        [0]     No likes yet.
        [one]   One person liked your message
       *[other] { $num } people liked your message
    }
```
The quote is, "the following examples are equivalent and will both work.".
In reality, things are somewhat different.
Firstly, the first snippet depends on the type of argument passed as $num. If $num is a string, like "1", the result will be "1 people liked your message". If $num is number 1, the result is "One person liked your message". This is mostly ok.
But with the second snippet here is a real problem.
Considering we want to cast our number "1" to FluentValue::Number, we can call it to make the conversion. And it works on the playground.
https://projectfluent.org/play/?id=c9aca30ef4ba09384df54def5b5ead01

In fluent-bundle, it doesn't work. Even worse, it doesn't work even if we call NUMBER if $num is already a number (for example to add more options).
I created a gist that shows those 4 cases.
https://gist.github.com/juliancoffee/ab6f8bf691415f20942debfdfe50cc4b

Results are following:
1 people liked your message ("1")
One person liked your message (1)
1 people liked your message (NUMBER("1"))
1 people liked your message (NUMBER(1))

[HIDDEN] I would gladly make a PR if that's appreciated.

### Additional contract requirements

- A function invoked in a selector expression must be evaluated, and its returned numeric value must be used to select the matching variant, whether the function's argument is a string or a number.
