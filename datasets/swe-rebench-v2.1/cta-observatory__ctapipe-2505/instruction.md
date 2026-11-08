Conflict between DIRAC python module and the ctapipe use of logging
Hi all,
I faced to a conflict between the use of logging within ctapipe and the python DIRAC API. Indeed the `logging` module gives the possibility to modify its configuration, in particular we can add new log level to the module. It's exactly what the DIRAC python module does.
The problem is that the `ctapipe.core.logging` module sets up the log for `ctapipe` but is expecting the initial configuration of the logging module. Indeed at https://github.com/cta-observatory/ctapipe/blob/8eaba747106bbb7ff35db020bed202d39a1fa4a1/src/ctapipe/core/logging.py#L29 the dictionary of log level name keywords is hard coded, I would suggest to write it with a more versatile way.

Steps to reproduce the behavior:
1. create a `tool` which inherits from the `ctapipe.core.tool` main class, this tool will do nothing
2. overwrite the setup method and add the following line :`from DIRAC.Interfaces.API.Dirac import Dirac`
3. create the tool, then run the `tool.setup()` and then try to do a `tool.log.warning("hello")`

I guess that this bug could appear as well if you are not doing this within a `tool`, but it's with the `tool` that I personally discovered its.

I get the following error showing that there is an error with  the color formatter of the log :
```
Traceback (most recent call last):
  File "/home/ggroller/.conda/envs/nectarchain/lib/python3.11/logging/__init__.py", line 1110, in emit
    msg = self.format(record)
          ^^^^^^^^^^^^^^^^^^^
  File "/home/ggroller/.conda/envs/nectarchain/lib/python3.11/logging/__init__.py", line 953, in format
    return fmt.format(record)
           ^^^^^^^^^^^^^^^^^^
  File "/home/ggroller/.conda/envs/nectarchain/lib/python3.11/site-packages/ctapipe/core/logging.py", line 22, in format
    return s.replace(record.levelname, apply_colors(record.levelname))
                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/ggroller/.conda/envs/nectarchain/lib/python3.11/site-packages/ctapipe/core/logging.py", line 38, in apply_colors
    levelname_color = color_seq % (30 + colors[levelname]) + levelname + reset_seq
                                        ~~~~~~^^^^^^^^^^^
KeyError: 'WARN'
```

[HIDDEN]

### Additional contract requirements

- Colored logging must not raise an error for an unrecognized or custom log-level name, including `WARN`; render such names in bold without a level-specific color.
