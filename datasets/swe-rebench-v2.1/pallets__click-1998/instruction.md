Consider not showing the default value of boolean flags without a secondary option (False)
Unless I'm missing something, the default value of such options should be obvious: `False`. As a consequence, `[default: False]` feels like superfluous noise. This is certainly true for the `--help` option, which should never show a default.
