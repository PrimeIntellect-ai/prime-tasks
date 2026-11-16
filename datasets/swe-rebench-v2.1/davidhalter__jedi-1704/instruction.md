How to figure out completion prefix without `completion.complete` in fuzzy mode?
Hi,

I'm trying to make IPython use fuzzy completion, however it doesn't work right now because `Completion.complete` [is None for fuzzy completions](https://github.com/davidhalter/jedi/commit/41a6591d88efcbf29832844e877b863a49d1d8ff).
From what I can see, IPython needs this field [to compute which prefix should be replaced](https://github.com/ipython/ipython/blob/master/IPython/core/completer.py#L1956) in the completion input. For example, if the current text is `os.ab` and there's an `abort(` completion, IPython needs to know that after accepting the completion the new text is `os.abort(` and not `os.ababort(` or something else.

Is there a way to get the same information with fuzzy completions?

Thanks

### Additional contract requirements

- Expose `Completion.get_completion_prefix_length()` to return the number of input characters in the current completion prefix, including for fuzzy completions, so callers can replace that prefix when applying a completion rather than duplicate it.
