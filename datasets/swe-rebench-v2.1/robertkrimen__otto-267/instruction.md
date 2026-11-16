array sort function bug with custom compare function
Array sorting is wrong if compare function returns abs(value) < 1 or abs(value) > 2147483647.
```
package main

import "github.com/robertkrimen/otto"

func main() {
vm := otto.New()
vm.Run(`
	console.log([0.5, 0.8, 0.2].sort(function (a,b) { return a-b; }));
	console.log([2147483647, -1, 1].sort(function (a,b) { return a-b; }));
	console.log([2e10, -2e10, 0].sort(function (a,b) { return a-b; }));
`)
}
```
produces
```
0.5,0.2,0.8
2147483647,-1,1
0,-200000000000,200000000000
```
