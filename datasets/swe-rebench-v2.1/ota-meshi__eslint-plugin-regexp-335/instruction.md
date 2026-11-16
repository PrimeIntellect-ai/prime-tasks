`no-useless-lazy` doesn't handle negated lookarounds correctly
**Description**
I just noticed that `no-useless-lazy` didn't report `/\b\w+?\b/` even though the lazy modifier is useless because the quantifier is effectively possessive.

![image](https://user-images.githubusercontent.com/20878432/134643916-03e50bc5-8783-403f-a562-30e44f8784dc.png)


```js
/* ✗ BAD */
var foo = /f\w+?(?=\W)/; // correct
var foo = /f\w+?\b/;     // false negative
var foo = /f\w+?(?!\w)/; // false negative
var foo = /f\w+?$/;      // false negative
```
