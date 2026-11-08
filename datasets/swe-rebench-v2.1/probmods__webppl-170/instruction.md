CPS doesn't handle 'empty return'
This program:
````
var foo = function() {
	if (flip(0.5))
		return;
	globalStore.count = globalStore.count + 1;
	foo();
};

MH(function() {
	globalStore.count = 0;
	foo();
	return globalStore.count;
}, 1000);
````
produces this error
````
/Users/dritchie/Git/webppl/src/transforms/cps.js:170
  switch (node.type) {
              ^
TypeError: Cannot read property 'type' of null
    at cps (/Users/dritchie/Git/webppl/src/transforms/cps.js:170:15)
    at Array.<anonymous> (/Users/dritchie/Git/webppl/src/transforms/cps.js:315:14)
    at Array.<anonymous> (/Users/dritchie/Git/webppl/src/syntax.js:30:27)
    at loop (/Users/dritchie/Git/webppl/src/syntax.js:50:24)
    at /Users/dritchie/Git/webppl/src/syntax.js:51:16
    at Array.<anonymous> (/Users/dritchie/Git/webppl/src/syntax.js:35:16)
    at loop (/Users/dritchie/Git/webppl/src/syntax.js:50:24)
    at /Users/dritchie/Git/webppl/src/syntax.js:51:16
    at Array.<anonymous> (/Users/dritchie/Git/webppl/src/syntax.js:35:16)
    at loop (/Users/dritchie/Git/webppl/src/syntax.js:50:24)
````
There's a workaround by using `return undefined;` instead of just `return;`, but IMO webppl should probably handle this better.

### Additional contract requirements

A bare `return;` must behave like returning `undefined`: it exits the current function immediately, including when it appears in a conditional branch.
