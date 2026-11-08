abs(0 + 0i) evaluates to NaN
Attempting to evaluate abs(0 + 0i) returns NaN. This appears to be an unnoticed edge case in avoiding overflows when calculating the absolute value of a complex number.

abs(0 + 0i) should, obviously, return 0.
