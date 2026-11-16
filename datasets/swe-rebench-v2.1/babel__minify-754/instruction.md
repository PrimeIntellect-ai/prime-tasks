Boolean return statements are changed to (un)defined by minify-simplify
#### Input Code

```js
function(object, property, value) {
    if (object && property) {
        object[property] = value;
        return true;
    }
    return false;
}
```

#### Actual Output
<!-- If an error is thrown, please provide the stack trace here -->

```js
return object && property && (object[property] = value, true);
```

#### Expected Output

```js
[HIDDEN]
```

#### Details
When a function returns true/false conditionally based on check of input parameters, this seems to be flattened into a single condition using logical operator && in between. Because of that the result of the above function behaves differently in case when input arguments (object, property) are not provided by the client call.

Calling the function originally with no parameters returns "false".
Calling the function after being transformed by minify-simplify with no parameters returns "undefined".

### Additional contract requirements

The transformed function must return `false` when its guard (`object && property`) is falsy, including when called without arguments. When that guard is truthy, it must perform the property assignment and return `true`, regardless of whether the assigned value is truthy or falsy.
