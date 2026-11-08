Bit field formatter
You can't use formatters with bitfields other than the last one in a sequence, [HIDDEN] Thus all the other bit field values get overwritten when the actual reading and bit shifting code is executed, because the formatters were called earlier.

**EDIT:**

It's been almost five years, but I thought I'd add a concrete example. 😄 I'm using `binary-parser@1.6.2` for these.

Here's a simple parser that parses uint8 values, and uses formatter for those (although these formatters just return a constant string).

```js
new Parser()
    .uint8('a', { formatter: () => 'first' })
    .uint8('b', { formatter: () => 'second' })
    .uint8('c', { formatter: () => 'third' });
```

The generated code is fine. First we read the value to the `vars` and then we immediately replace that value with the formatted version.

```js
vars.a = dataView.getUint8(offset, false);
offset += 1;
vars.a = (() => 'first').call(this, vars.a);

vars.b = dataView.getUint8(offset, false);
offset += 1;
vars.b = (() => 'second').call(this, vars.b);

vars.c = dataView.getUint8(offset, false);
offset += 1;
vars.c = (() => 'third').call(this, vars.b);
```

Here's the same thing, except we're parsing bitfields. We're still using formatters.

```js
new Parser()
    .bit8('a', { formatter: () => 'first' })
    .bit8('b', { formatter: () => 'second' })
    .bit8('c', { formatter: () => 'third' });
```

Now there's a bug in the generated code:

```js
vars.a = (() => 'first').call(this, vars.a);  // Formatter called with vars.a being undefined
vars.b = (() => 'second').call(this, vars.b); // Same with vars.b
var $tmp1 = dataView.getUint16(offset);
var $tmp2 = dataView.getUint8(offset + 2);
var $tmp0 = ($tmp1 << 8) | $tmp2;
offset += 3;
vars.a = $tmp0 >> 16 & 255; // The values are finally parsed
vars.b = $tmp0 >> 8 & 255;
vars.c = $tmp0 >> 0 & 255;
vars.c = (() => 'third').call(this, vars.c); // But only the last one is properly formatted
```

When parsing multiple successive bitfields, [HIDDEN] Thus the formatters get called too early, when the values don't exist yet.

[HIDDEN]
bit32 always returns 0
``` js
require('binary-parser').Parser.start().bit32('a').getCode()
```

returns

``` js
var vars = {};
var offset = 0;
if (!Buffer.isBuffer(buffer)) {
throw new Error("argument buffer is not a Buffer object");
}
var $tmp0 = buffer.readUInt32BE(offset);
offset += 4;
vars.a = $tmp0 >> 0 & 0;
return vars;
```

Please note the `& 0`, which will always lead to the result `0`.

Bugs with .bitN functions
It seems the `.bitN` functions don't always respect `options` passed to them. However, `.nest`-ing them in a new parser does cause them to respect `options`, unless the `nest`-ed `.bitN` functions align to a byte.

Additionally, `.nest`-ed parsers consume up to the next byte boundary, even when only parsing `.bitN` functions.

Examples:
https://repl.it/Klzf/20
.bit2 formatter don't work
.bit2('Sensor', { formatter: function (Sensor) { console.log(Sensor) } });

console.log is empty

bit field sequence longer than 4-bytes
I have a bit field described as follows:

[bit12][bit12][bit12][bit2][bit12]...

However, I get the error "bit field sequence longer than 4-bytes is not suported." I understand why the error is occurring. How do I parse this?

Thanks for great software!
Formatter and assert functions called too early for bitN()
Hi all.

I would like to format multi-bit field result. I define formatter function but as seen from the generated code, formatter is called before the actual bitfield is extracted. Same holds true for assert function for bitfields.
I assume formatting was not intended functionality for bitfields, but for my payload parsers it would be super-duper awesome.

Original code:
```
var Parser = require("binary-parser").Parser;

var test_sub = new Parser()
  .endianess('little')
  .bit3("my_param", {
      formatter: function(arg) {
        console.log(arg);
        return arg*arg; // should modify the value
      }
  })
  .bit5("the_other_param")

var test_parser = new Parser()
  .endianess('little')
  .uint8("packet_type", { assert: 0x04 })
  .nest("bitfields", {"type":test_sub});

var buf = Buffer.from("0482", "hex");

var res = test_parser.parse(buf);
console.log(JSON.stringify(res, null, 2));
```

Compiled code:
```
(function anonymous(imports,TextDecoder
) {
return function (buffer, constructorFn) { var dataView = new DataView(buffer.buffer, buffer.byteOffset, buffer.length);
var offset = 0;
var vars = {};
vars.packet_type = dataView.getUint8(offset, false);
offset += 1;
if (4 !== vars.packet_type) {
throw new Error("Assert error: vars.packet_type is " + 4);
}
vars.bitfields = {};
vars.bitfields.my_param = imports[0].call(this, vars.bitfields.my_param); // tries to modify but its undefined here
var $tmp0 = dataView.getUint8(offset);
offset += 1;
vars.bitfields.my_param = $tmp0 >> 0 & 7; // after calling the formatter now it extracts the value
vars.bitfields.the_other_param = $tmp0 >> 3 & 31;
return vars;
 };
})
```

Console output:
```
undefined
{
  "packet_type": 4,
  "bitfields": {
    "my_param": 2,
    "the_other_param": 16
  }
}
```

### Additional contract requirements

- For each bit field with a formatter, including non-final fields in a consecutive sequence and fields in a nested parser, apply the formatter to the extracted field value and store its result. Bit-field assertions must also be evaluated against the extracted value.
- Consecutive bit-field sequences must support any length permitted by the input and field definitions; they must not be limited to four bytes.
