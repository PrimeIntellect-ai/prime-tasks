minifier: Expand an argument with a spread with an array
### Describe the feature

```js
function logTheNine() {
    ((theThree, theNine)=>{
        console.log(theNine);
    })(...[
        3,
        9
    ]);
}
logTheNine();


```

=>

```js
function logTheNine() {
    ((theThree, theNine)=>{
        console.log(theNine);
    })(
        3,
        9
    );
}
logTheNine();


```

### Babel plugin or link to the feature description

_No response_

### Additional context

_No response_

### Additional contract requirements

The complete minified output of the example above is:

```js
function logTheNine() {
    console.log(9);
}
logTheNine();
```
