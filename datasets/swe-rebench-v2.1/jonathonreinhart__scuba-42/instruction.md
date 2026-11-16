utils.format_cmdline misses last line
It appears that utils.format_cmdline fails to yield the last accumulated line.

This also means that a better test could be written, which splits the result back out, and compares it to the list of input arguments.
