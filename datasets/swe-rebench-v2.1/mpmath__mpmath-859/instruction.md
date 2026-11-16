format(mp.mpf(0.99999), '.4f') returns '0.99999'
Should be '1.0000'.

I would guess this is related to "a hack" here:
https://github.com/mpmath/mpmath/blob/9d9029a5592124670dd6efd89c26b0c2304d272e/mpmath/libmp/libmpf.py#L1519-L1522

CC @javierelpianista

### Additional contract requirements

- Also, `format(mp.mpf(0.96875), '#.0g')` should return `'1.'`.
