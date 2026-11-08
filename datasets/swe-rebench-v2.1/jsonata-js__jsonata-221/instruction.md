numeric precision should be 15 decimal digits, not 13
With the JavaScript implementation on try.jsonata.org I am getting only 13 decimal digits of precision with numeric data ... when I expected 15. I am observing this behavior in Chrome + FireFox + Safari.

see http://try.jsonata.org/r1SPLIKjz

IEEE 754 double (binary64) gives you 53 bits of significand. This gives one a reliable 15 decimal digits of precision.

[ If I invoke jsonata-1.1.1.js using the nashorn scripting engine of Java 1.8.0_152 then numeric data is retains its full IEEE value ... unless I explicitly call JSONata $string(). ]

[HIDDEN]
                    [HIDDEN] :
                    (val && isFunction(val)) ? '' : val;`

My initial thought was/is that it would be best to leave the numbers alone and let `JSON.stringify()` handle it. Yet, there must have been some negative behavior that led to this code being added.

Q: What was the issue that caused numbers to be treated this way?

If there is a good reason for rounding to a specific decimal precision, then the precision should be set to 15, not 13.

### Additional contract requirements

- When JSONata’s `$string()` converts a numeric value to a string, it should retain 15 significant decimal digits of precision rather than round to 13.
