Update handling of breaking around binary operators: W503 vs W504
Based on the discussion that started on python-dev [1] and ended with an update to PEP-8 [2][3], the logic for allowing (preferring really) breaks to occur before rather than after binary operators.

[1] https://mail.python.org/pipermail/python-ideas/2016-April/039774.html
[2] http://bugs.python.org/issue26763
[3] https://hg.python.org/peps/rev/3857909d7956

### Additional contract requirements

- By default, `options.ignore` must be `('E121', 'E123', 'E126', 'E226', 'E24', 'E704', 'W503')`.
