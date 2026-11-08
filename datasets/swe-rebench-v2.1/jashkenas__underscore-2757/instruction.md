1.9 regression failing in groupBy
Hi folks, I couldn't find an issue containing the `groupBy` function. So I'm creating one. Please redirect if I missed anything. Thanks for all the hard work. Appreciate it!

When updating from version 1.8.3 to 1.9.0 the behaviour of `groupBy` changed in a way that grouping by arrays was possible in 1.8.3, but it's not possible in 1.9.0. At least not as I'm expecting it to work 🤔

The below test would succeed in 1.8.3 where it throws an exception in 1.9.0. Am I doing something wrong?

```javascript
var anArray = [1,2];
var list = [{
	arrayProp: anArray,
	otherProp: 1
}, {
	arrayProp: anArray,
	otherProp: 2
}];

var res = _.groupBy(list, 'arrayProp');
// var res = _.groupBy(list, function(element) {
//  	// stringified version of key is equal and gets grouped
//  	return JSON.stringify(element.arrayProp);
// });
var groupByKey = Object.keys(res)[0];
console.log(Object.keys(res).length) // 1
console.log(groupByKey); // 1,2

var expected = 2
var actual = res[groupByKey].length;
if (actual !== expected) {
	throw new Error("TEST FAILURE. EXPECTED " + 2 + ". GOT " + actual)
}
```

`-> Uncaught Error: TEST FAILURE. EXPECTED 2. GOT 1`
