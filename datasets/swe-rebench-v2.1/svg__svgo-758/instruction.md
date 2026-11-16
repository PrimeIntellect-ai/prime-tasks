shofthex: false does not transform ff0000 to red
With default settings (which includes shortname: true):
<g color="#ff0000"/>
is optimized to:
<g color="red"/>

When setting:
{ "shorthex": false }

the same behavior is expected but the color remains:
<g color="#ff0000"/>

### Additional contract requirements

When `shorthex` is false, `#ff0000` is still optimized to the equivalent named color `red`; it must not remain in its full-length hexadecimal form.
