Allow adding a custom validation error at a given array index
There's currently no way to declare a custom validation error at a given position in an array value. Would be nice to expose an API for that, eg.:

``` js
function validate({myArray}, errors) {
  if (myArray[1] !== "foo") {
    errors.myArray[1].addError("Nope.");
  }
  return errors;
}
```
