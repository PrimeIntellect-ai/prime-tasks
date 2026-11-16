Investigate off-by-1 in `scrapy.cmdline._pop_command_name()`
It looks like `del argv[i]` removes the wrong item in `scrapy.cmdline._pop_command_name()` but as we don't seem to see any problems because of this it's worth investigating what exactly happens here and either fixing or refactoring the code.
