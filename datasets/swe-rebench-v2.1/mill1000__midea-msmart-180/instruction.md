Binary formatted total & current energy are off by a factor of 10
As originally reported here: https://github.com/mill1000/midea-ac-py/issues/230

Some users report that the total and current energy sensors are much to high. We are estimating by roughly a factor of 10 but haven't been able to conclusively determine if that's true.

I can't find any reference in the Lua or JS to this divide by 10.

Creating this issue just to track.

### Additional contract requirements

- For binary-formatted energy responses, the reported total and current energy values must each be one tenth of the corresponding values indicated by the response.
