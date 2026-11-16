@ is not considered as A Special Character in "isStrongPassword" function
**Description**
**isStrongPassword** function is not considering '@' as a Special Character

**Example**
```
(() => {
    const validator = require('validator');
    console.log(validator.isStrongPassword('Aa1Bb2Cc3!'));
    console.log(validator.isStrongPassword('Aa1Bb2Cc3@'));
    console.log(validator.isStrongPassword('Aa1Bb2Cc3#'));
})()
```

Output ---
```
true
false
true
```
