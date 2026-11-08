d3.bin should check for null
Our threshold implementations do already, which is good (via count), but we shouldn’t be passing null values in here:

https://github.com/d3/d3-array/blob/6fda2773d31c2b3377d8b2dbd11a3e334a7cbc9e/src/bin.js#L80-L82

(Undefined and NaN values already fail this test, so we’re good on those.)

### Additional contract requirements

A sample must not be assigned to a bin when the value produced for it by the value accessor is null, even if the sample itself is non-null.
