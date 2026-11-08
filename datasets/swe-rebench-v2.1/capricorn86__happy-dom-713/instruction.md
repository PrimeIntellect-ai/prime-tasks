setTimeout / setInterval does not pass arguments to callback
**Describe the bug**
Arguments to callback function of setTimeout or setInterval doesn't receivce arguments.

**To Reproduce**
Execute in browser:
```
const callback = (message) => {console.log(message)};
setTimeout(callback, 0, 'hello');

VM154:1 hello
```

Execute in happy-dom:
```
const callback = (message) => {console.log(message)};
setTimeout(callback, 0, 'hello');

VM154:1 undefined
```

**Expected behavior**
Should print hello as the browser.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Device:**
 - Version 8.2.3
