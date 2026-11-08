Allow dictionary search to take multiple substrings
### Description

Currently, the `search` method for dictionaries (in `util.py`) only takes a string. I would be useful to be able to provide a list of strings so it checks for all of them.

### Motivation

It would allow for more specific searches. For example, let's say I want a given overpotential in the negative electrode but can't recall the name. I could search for "[V]" and "negative" to whittle down the list.

### Possible Implementation

For the `search` method it would be fairly straightforward, [HIDDEN]

For the `get_best_matches` (which is used if the search is unsuccesful) it is less obvious how to fix it as, from what I understand, the `difflib.get_close_matches` method does not allow for multiple strings to check.

### Additional context

_No response_

### Additional contract requirements

Search accepts either a single string or a list of strings. For a list, each matching key must contain every supplied substring.
