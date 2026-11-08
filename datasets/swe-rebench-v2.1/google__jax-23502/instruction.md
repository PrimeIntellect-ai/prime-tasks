jax.debug.print() fails when passing value formatting (which docs say is supported)
### Description

`jax.debug.print()` supports printing variable values, e.g.: `a = 5; jax.debug.print("{}", a)` outputs `5`. And this works inside of a function that has been JAX compiled as well.

And when called **without** any compiling, it supports formatting values in the standard way, e.g. `a = 5; jax.debug.print("{:.2f}", a)` outputs `5.00`.

But if you attempt to include any value formatting **in a compiled function**, then running the function **produces an error:**

```
def kernel(a):
  jax.debug.print("{:.2f}", a)
compiled = jax.jit(kernel)
compiled(5)
```

```
TypeError: unsupported format string passed to DynamicJaxprTracer.__format__
```

Yet the [documentation for jax.debug.print](https://jax.readthedocs.io/en/latest/_autosummary/jax.debug.print.html#jax.debug.print) clearly states:

> fmt (str) – A format string, e.g. "hello {x}", that will be used to format input arguments, like str.format. See the Python docs on string formatting and format string syntax.

I've encountered this bug because I'm using `jax.debug.print()` to monitor several values at a time during execution to debug it, and I'd like the rows of values to be of a similar length to make the columns more readable. Dealing with floats that might print `10.119900703430176` or might print `2` makes for a debugging experience that is harder to read.

Here is a [Colab notebook](https://colab.research.google.com/drive/1xWYGHzZHXpV10LClTyB_zYJGIVEHUBL2?usp=sharing) with example code that you can see the results and run yourself.

### System info (python version, jaxlib version, accelerator, etc.)

Running on current Google Colab.

```
jax:    0.4.26
jaxlib: 0.4.26
numpy:  1.26.4
python: 3.10.12 (main, Jul 29 2024, 16:56:48) [GCC 11.4.0]
jax.devices (1 total, 1 local): [CpuDevice(id=0)]
process_count: 1
platform: uname_result(system='Linux', node='afb8abe17318', release='6.1.85+', version='#1 SMP PREEMPT_DYNAMIC Thu Jun 27 21:05:47 UTC 2024', machine='x86_64')
```
