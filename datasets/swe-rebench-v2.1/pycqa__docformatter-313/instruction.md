Multiple sentences in multi-line docstring summary
When reading [PEP 257](https://peps.python.org/pep-0257/), I am under the impression that the one line summary at the beginning of the docstring should only be composed of a single sentence, from [`One-line Docstrings`](https://peps.python.org/pep-0257/#one-line-docstrings):

> The docstring is a phrase ending in a period. It prescribes the function or method’s effect as a command (“Do this”, “Return that”), not as a description; e.g. don’t write “Returns the pathname …”.

From what I have tested, this seems correctly enforced in `docformatter` with single line docstrings. But shouldn't it also be enforce with multi-line docstrings? From [`Multi-line Docstrings`](https://peps.python.org/pep-0257/#multi-line-docstrings):

> Multi-line docstrings consist of a summary line just like a one-line docstring, followed by a blank line, followed by a more elaborate description

From what I have tested:

```py
def foo():
    """Do bar. This is the first sentence. And this is the second.

    And now this is the longer description.
    """
```

Is not reformatted by `docformatter` (`1.75`).

But:

```py
def foo():
    """Do bar. This is the first sentence. And this is the second."""
```

gets (correctly) reformatted into:

```py
def foo():
    """Do bar.

    This is the first sentence. And this is the second.
    """
```

Is this an inconsistency or am I wrong in my interpretation? Thanks!

### Additional contract requirements

- Add a public function `split_summary(lines: List[str]) -> List[str]` in the
  `docformatter.strings` module, importable as `docformatter.split_summary`.
- `split_summary` replaces the first element of `lines` with its first sentence.
  If that first element contains additional sentences, they are inserted as a new
  paragraph after a blank line, at index 2 of the returned list, while the rest of
  the line structure is preserved.
- An empty input, or an input whose first line is empty or whitespace-only, is
  returned unchanged. The function always returns a list of strings and never
  returns `None`.
- `split_summary_and_description` splits a multi-sentence summary line of a
  multi-line docstring so that only the first sentence is returned as the summary
  and the remaining sentences are prepended to the description.
