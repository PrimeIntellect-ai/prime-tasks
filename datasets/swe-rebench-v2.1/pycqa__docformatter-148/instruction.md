URL matching only matches certain schemes, not others
Specifically it split up an `s3` scheme URL :sob:

Likely due to this: https://github.com/PyCQA/docformatter/blob/6706e9591c9f605956372eb1ee6228c465e0ac93/src/docformatter/syntax.py#L114
