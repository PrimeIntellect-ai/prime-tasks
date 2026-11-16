math.intersect() is numerically unstable.
Example:
math.intersect([300, 90], [400, 97], [300, 130], [400, 125]) returns null.

The current code has a hard equivalence check which should probably be [HIDDEN].

### Additional contract requirements

- For this input, `math.intersect([300, 90], [400, 97], [300, 130], [400, 125])` must return `[633.3333333333334, 113.33333333333334]`.
- For 2D lines that truly intersect, floating-point roundoff must not cause `math.intersect` to return `null` solely because independently computed coordinates fail an exact equality comparison.
