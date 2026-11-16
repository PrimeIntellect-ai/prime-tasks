Add rule for Resizable and growable ArrayBuffers
[Resizable and growable ArrayBuffers](https://github.com/tc39/proposal-resizablearraybuffer) has reached stage 4.

https://github.com/tc39/proposal-resizablearraybuffer

I think we need to add a rule to prohibit them.

- The second (`option`) argument to `ArrayBuffer` constructor.
- ArrayBuffer.prototype.maxByteLength
- ArrayBuffer.prototype.resizable
- ArrayBuffer.prototype.resize()
- The second (`option`) argument to `SharedArrayBuffer` constructor.
- SharedArrayBuffer.prototype.grow()
- SharedArrayBuffer.prototype.growable
- SharedArrayBuffer.prototype.maxByteLength

### Additional contract requirements

- Add the rule `es-x/no-resizable-and-growable-arraybuffers`, provided by the module `lib/rules/no-resizable-and-growable-arraybuffers.js`.
- A constructor call is not reported when either of its first two arguments is a spread element, for example `new ArrayBuffer(8, ...args)` or `new ArrayBuffer(...args, { maxByteLength: 16 })`.
