Enhance `isComparable` function for full Comparable interface implementation
Hello, this is my first created issue, if there is something wrong just tell me!

The current implementation of the [isComparable](https://github.com/harttle/liquidjs/blob/master/src/drop/comparable.ts#L11) function only checks if the `equals` method is present on the object. This is leading me to issues when I'm using a custom Drop class that casually also has an implementation of `equals`, but I don't want to make it an implementation of the `Comparable` interface.

When I use the operators `<`, `>`, `<=`, and `>=` the class is detected as an implementation of Comparable and tries to execute the related functions. This happens in the [operator code](https://github.com/harttle/liquidjs/blob/master/src/render/operator.ts#L16).

### Proposed Solution
[HIDDEN]

I made a fork and a PR for this. I will link it right now.

### Benefits
This will ensure that objects are properly evaluated and that they will use the proper comparison functions, improving the robustness of the template evaluation for the operators `<`, `>`, `<=`, and `>=`.

Please let me know if this enhancement is acceptable or if there are any changes or additional considerations I should take into account.

### Additional contract requirements

- An object should be treated as Comparable for comparisons only when it provides callable `equals`, `gt`, `geq`, `lt`, and `leq` methods. An object with only an `equals` method must not be treated as Comparable by relational operators.
