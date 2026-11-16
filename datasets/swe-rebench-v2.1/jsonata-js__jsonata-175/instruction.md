Semantic Issue in Object Grouping
I noticed, while reviewing the evaluation code, that there is what I think is an incorrect assumption.  The evaluation for objects appears to work as follows:

We loop over each input value.  We evaluate the `key` expression in the context of that input value.  [HIDDEN]  I'm pretty sure this isn't correct and it creates some odd issues.  For example, imagine our input (for all cases I'm going to consider) is:

```json
[
  {
    "key": "foo",
    "value": 5
  },
  {
    "key": "bar",
    "value": 10
  }
]
```

Now if I evaluate this: `{ key: value }`, I get pretty much what you might expect, *i.e.,* `{ "foo": 5, "bar": 10 }`.

So far so good.  If I evaluate `{ key: (value+1) }`, I also get pretty much what I would expect: `{ "foo": 6, "bar": 11 }`.

Now how about if I evaluate: `{ key: value, key: value }`.  Now we have **overlapping values for the key expressions**.  That's actually ok and it works (and I think it is reasonable to allow overlapping key expressions, BTW).  It evaluates to:

```json
{
  "foo": [
    5,
    5
  ],
  "bar": [
    10,
    10
  ]
}
```

I'm no so sure this is the most intuitive result.  Some might expect the second to *overwrite* the first in this case (*i.e.*, some might expect `{ "foo": 5, "bar": 10 }`), but it doesn't.  Instead, it appends the results.  But at least we get an answer that we can explain even if it might seem unintuitive.

But now things start to misbehave.  Imagine I evaluate this instead: `{ key: value, key: value+1 }`.  I get the same answer as for `{ key: value, key: value }`.  [HIDDEN] `value+1` **is never evaluated**.  But things can actually get worse.  If you switch the order and try to evaluate `{ key: value+1, key: value }` you actually get an error that it cannot evaluate `value` because it isn't a number.

Now, one thing you can do is change the semantics slightly so you actually evaluate the `value` expressions immediately in the context of each input value (rather than storing them up).  This actually makes sense for the `value+1` case and seems reasonably intuitive.  Said another way, it may be more intuitive to do the evaluate this way because I suspect it is what people would expect.  But, this will actually breaks one of the test cases, *i.e.,* the containing the expression:

```Account.Order.Product{$string(ProductID): (Price)[0]}```

Because the `[0]` in there become meaningless because `Price` always evaluates to a scalar rather than an array.  So that approach would change the semantics slightly.  Presumably the `[0]` is there specifically to grab the first value.

The alternative is to append not just each successive input value associated with each key but also each unique value expression as well (instead of just the first one).  I suspect you'd probably want this alternative but I wanted to thoroughly explain the problem and collect feedback to be sure.

To be honest, implementing these evaluation semantics is a bit complicated.  Furthermore, that error for `value+1` is pretty confusing and unintuitive.  So before working on implementing anything more (I've implemented a couple different approaches already), I thought it would be good to discuss what is most intuitive.

Any comments?

### Additional contract requirements

- When a single object constructor `{...}` contains more than one key/value clause and the same key is produced by two or more different clauses, evaluation must fail with a dynamic error whose `code` is `D1009`. This applies even when the clauses are textually identical, for example `{ key: value, key: value }`.
- When the same key is produced by a single clause across multiple input items, the corresponding values are appended into an array.
- When clauses produce distinct keys, each key's value is evaluated using the value expression from the clause that produced that key.
