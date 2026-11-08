Ensure that docstrings pass numpydoc validation
### Background / Objective

[Docstrings](https://www.python.org/dev/peps/pep-0257/#what-is-a-docstring) in Python are string literals that occur as the first statement in a module, function, class, or method definition.

These are some of the characteristics of a docstring:

- Triple quotes are used to encompass the docstring text.
- There is no blank line before or after the docstring.
- The docstring is a phrase ending in a period.
- [more details](https://www.python.org/dev/peps/pep-0257/#what-is-a-docstring)

[numpydoc](https://numpydoc.readthedocs.io/en/latest/format.html) is one set of criteria to check for consistent documentation structure.

### Validating docstrings in dirty_cat

To ensure consistent documentation structure in dirty_cat, we are using numpydoc validation. Currently, documentation tests are failing for various functions. As a temporary fix, we have suppressed error messages in [test_docstrings.py](https://github.com/dirty-cat/dirty_cat/blob/master/dirty_cat/tests/test_docstrings.py). Many of the functions in dirty_cat need to be updated to comply with numpy docstring validation. In the below issue, we provide step-by-step instructions on how contributors can test and update functions.

### Steps

1. Make sure you have the development dependencies and documentation dependencies installed (see [the contribution guidelines](https://github.com/dirty-cat/dirty_cat/blob/master/CONTRIBUTING.rst)).
2. Pick a function/class from the list below and leave a comment saying you are going to work on it. This way we can keep track of what everyone is working on.
2.1 Make sure you've created a separate branch from main before editing files for your new contribution. Refer to our [contributing guidelines](https://github.com/dirty-cat/dirty_cat/blob/master/CONTRIBUTING.rst) for more information.
3. Remove the function from the list `DOCSTRING_TEMP_IGNORE_SET` in [`test_docstring.py`](https://github.com/dirty-cat/dirty_cat/blob/master/dirty_cat/tests/test_docstrings.py#L22).
5. Let's say you picked `dirty_cat.gap_encoder.GapEncoder.fit`, run numpydoc validation as follows.
```commandline
pytest dirty_cat/tests/test_docstrings.py
```

6. If you see the test fails, please fix them by following the recommendation provided by the failing test.
7. If you see all the tests pass, you do not need to do any additional changes.
8. Commit your changes.
9. Open a Pull Request with an opening message Addresses #345. Note that each item should be submitted in a separate Pull Request.
10. Include the function name in the title of the pull request. For example: *"DOC Ensures that GapEncoder.fit passes numpydoc validation"*.

Note: once you have issued 1-2 such PRs, feel free to move on to contributing more complex pull requests that involve more thinking and leave the other fixes to first time contributors for them to learn the github contribution workflow :)

### Functions to Update

- [X] `dirty_cat._datetime_encoder.DatetimeEncoder` #421
- [x] `dirty_cat._datetime_encoder.DatetimeEncoder.fit` #367
- [ ] `dirty_cat._datetime_encoder.DatetimeEncoder.get_feature_names`
- [ ] `dirty_cat._datetime_encoder.DatetimeEncoder.get_feature_names_out`
- [x] `dirty_cat._datetime_encoder.DatetimeEncoder.transform` #368
- [x] `dirty_cat._gap_encoder.GapEncoder` #438
- [X] `dirty_cat._gap_encoder.GapEncoder.fit` #439
- [ ] `dirty_cat._gap_encoder.GapEncoder.get_feature_names`
- [ ] `dirty_cat._gap_encoder.GapEncoder.get_feature_names_out`
- [ ] `dirty_cat._gap_encoder.GapEncoder.partial_fit`
- [ ] `dirty_cat._gap_encoder.GapEncoder.score`
- [ ] `dirty_cat._gap_encoder.GapEncoder.transform`
- [ ] `dirty_cat._minhash_encoder.MinHashEncoder`
- [ ] `dirty_cat._minhash_encoder.MinHashEncoder.fit`
- [X] `dirty_cat._minhash_encoder.MinHashEncoder.transform` #439
- [ ] `dirty_cat._similarity_encoder.SimilarityEncoder` #504
- [X] `dirty_cat._similarity_encoder.SimilarityEncoder.fit` #439
- [X] `dirty_cat._similarity_encoder.SimilarityEncoder.transform` #439
- [ ] `dirty_cat._similarity_encoder.SimilarityEncoder.fit_transform`
- [x] `dirty_cat._table_vectorizer.TableVectorizer` #399
- [X] `dirty_cat._table_vectorizer.TableVectorizer.fit_transform` #439
- [ ] `dirty_cat._table_vectorizer.TableVectorizer.transform`
- [ ] `dirty_cat._table_vectorizer.TableVectorizer.get_feature_names`
- [ ] `dirty_cat._table_vectorizer.TableVectorizer.get_feature_names_out`
- [ ] `dirty_cat._target_encoder.TargetEncoder`
- [X] `dirty_cat._target_encoder.TargetEncoder.fit` #439
- [X] `dirty_cat._target_encoder.TargetEncoder.transform` #439
- [ ] `dirty_cat._fuzzy_join.fuzzy_join`
