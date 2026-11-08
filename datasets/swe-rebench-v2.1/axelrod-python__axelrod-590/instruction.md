Make log scale in eco plot optional
Just nice to be able to change it back to a normal scale if we don't want to reproduce for a power of ten turns. (PR incoming, it's a 1 liner.)

### Additional contract requirements

An ecological plot can use a normal (linear) x-axis instead of the logarithmic x-axis. `Plot.stackplot` accepts the `logscale` option for this purpose; passing `False` uses a linear x-axis.
