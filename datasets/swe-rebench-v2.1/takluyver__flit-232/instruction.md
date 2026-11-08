requires-python parsing too picky
I had `requires-python = ">= 3.7"` and `flit build` made a wheel tagged `-py2.py3-none-any.whl`

If I put `requires-python = ">=3.7"` then I get the desired `-py3-none-any.whl`
