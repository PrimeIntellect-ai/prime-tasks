Mention filename when suggesting that user add a docstring
This one's more of a nicety.

Instead of the current message, when a docstring is missing, it would be nicer to have the path to the file suggested as well.

---

Suggesting changing:

> Cannot package module without docstring, or empty docstring. Please add a docstring to your module.

to something like:

> Cannot package module without docstring, or empty docstring. Please add a docstring to your module (/Users/pradyunsg/Projects/flit-trial/myscript.py).
