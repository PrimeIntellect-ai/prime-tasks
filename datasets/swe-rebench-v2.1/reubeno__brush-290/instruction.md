Implement brace expansion
For compatibility, brace patterns like `{a,b}` and `{1..10}` need to be expanded in (unquoted pieces of) words. There's a test case in `word_expansion.yaml` (marked as a `known_failure`) tracking some of the expectations.
