Stack overflow in array:flatten for very large arrays
See the following playground example: https://xpath.playground.fontoxml.com/?state=H4sIACFKG2MAAzVMWwqDMBC8ynS%2FFARrP4PNHXqEtd1CIRpIV1FC7u4qOD%2FzYGYyjfEj5LqGFk4%2FHoL8yVEu1NA6BpO9UesP%2B5olbZZwSrwho%2BqgEY%2B7ocYN%2FRC49Sh4epwV9w2sKlNVw%2BbvOKmsep1Q2QEhXQJZewAAAA%3D%3D

Expected: sequence of the 20k items in the array
Actual: stack overflow in both Chrome and Firefox

I wasn't able to determine exactly where the infinite recursion happens. The `flattenItem` function is recursive, but only along the structure of the array, which is flat in this case. The stack trace seen in the debugger implies the actual overflow happens in a repeating series of `next()` calls (note the repeating column numbers):

```
"RangeError: Maximum call stack size exceeded
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:444843)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:447687)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:444914)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:464694)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:444914)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:447687)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:444914)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:464694)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:444914)
    at Object.next (https://xpath.playground.fontoxml.com/static/js/1.7d5907a9.chunk.js:1:447687)"
```
