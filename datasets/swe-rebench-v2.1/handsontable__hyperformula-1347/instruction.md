[Bug]: in-built function SUBSTITUTE does not work as expected
### Description

I am looking for a way to convert values that end in decimal point to number. For example I would like `"13."` to be converted to `13`

## issue 1.
in excel `NUMBERVALUE` function does the job. NUMBERVALUE("13.") results in 13
But I did not see it as one of the supported built-in functions. So I thought perhaps i could use `SUBSTITUTE`, and then run into this bug

## issue 2.

```
import { HyperFormula } from 'hyperformula';
describe('hyperformula', () => {
  it('does not substitute correctly', () => {
    const hfInstance = HyperFormula.buildFromArray([], {
      licenseKey: 'gpl-v3',
    });

    const goodFormula = '=SUBSTITUTE("13x", "x", "x00")';

    const result1 = hfInstance.calculateFormula(goodFormula, 0);
    expect(result1).toStrictEqual('13x00');

    // in the formula below I was expecting it to behave
    // just like the one above, but it doesn't.
    // it returns ".00.00.00"
    const badFormula = '=SUBSTITUTE("13.", ".", ".00")';
    const result2 = hfInstance.calculateFormula(badFormula, 0);
    expect(result2).toStrictEqual('13.00');
  });
});
```


### Video or screenshots

_No response_

### Demo

I have added test code above to reproduce.

### HyperFormula version

2.4.0

### Your framework

plain javascript.

### Your environment

Node v16.18.0, MacOS 12.5

### Additional contract requirements

`SUBSTITUTE` treats its search string as literal text, not as a pattern. Characters that can have special meaning in regular expressions (including `.`, `*`, `+`, `?`, `^`, `$`, `{`, `}`, `(`, `)`, `|`, `[`, `]`, and `\\`) match themselves. This applies whether all matches or a particular occurrence is replaced.
