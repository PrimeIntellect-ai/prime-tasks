Flake8 Severity too high
After https://github.com/python-lsp/python-lsp-server/pull/234, all Flake8 codes starting with "F" are reported with error severity. This is overly high: the only codes that really errors are F821, F823, F831, and _maybe_ F405 and F822.

Can we add explicit checks for error codes to classify them as errors vs. warnings?
