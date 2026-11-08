Incorrect output for premature UNB delimiter (EDIFACT)
From @javaduke in Gitter channel (https://gitter.im/xlate/staedi)

```
'UNA:+.? '
UNB+UNOA:3
UNH+00000000000117+CONTRL:4:1:UN'
UCI+00000000000778+1+1+8++++'
UNT+1+00000000000117'
UNZ+1+00000000000778'
```
> note the single quote before UNA and no single quote at the end of the UNB

### Additional contract requirements

- For EDIFACT, when an UNB segment ends prematurely, preserve the segment boundary before emitting the following segment.
