Client registration sends ct with invalid syntax
I tried the Leshan demo client towards a non-Leshan server and noticed that the client uses invalid syntax in the Register operation payload:

```
</>;ct=60 110 112 11542 11543;rt="oma.lwm2m",</1>;ver=1.1,</1/0>,</3>;ver=1.1,</3/0>,</6/0>,</3303>;ver=1.1,</3303/0>
```

The syntax for `ct` is given in RFC 7252 (CoAP) as follows:

```ABNF
ct-value =  cardinal
         /  DQUOTE cardinal *( 1*SP cardinal ) DQUOTE
```

Even in the absence of RFC 7252 there is an ABNF in RFC 6690 (CoRE link format) that does not allow space in unquoted values.

Leshan should quote the `ct` attribute if it contains spaces, like so:

```
</>;ct="60 110 112 11542 11543";rt="oma.lwm2m",</1>;ver=1.1,</1/0>,</3>;ver=1.1,</3/0>,</6/0>,</3303>;ver=1.1,</3303/0>
```

Leshan's own parser for this data is very forgiving (too forgiving, really) which is probably why this was not caught right away.

### Additional contract requirements

- When processing a registration whose root link has `ct=0 42 11543` or `ct="0 42 11543` (without a closing quote), accept the registration and ignore that `ct` value when determining supported content formats. The supported formats must contain only `ContentFormat.TLV`.
