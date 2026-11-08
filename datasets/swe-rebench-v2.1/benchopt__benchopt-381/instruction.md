BUG invalid name dataset `rcv1.binary` all benchmarks
Since PR #362 merge, the dataset `rcv1.binary` leads to a `ValueError` I think because of the `.`
```
Traceback (most recent call last):
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 575, in _extract_parameters
    return ast.literal_eval(string)
  File "/home/tlefort/condaenvs/phd/benchopt_benchmark_logreg_l1/lib/python3.8/ast.py", line 59, in literal_eval
    node_or_string = parse(node_or_string, mode='eval')
  File "/home/tlefort/condaenvs/phd/benchopt_benchmark_logreg_l1/lib/python3.8/ast.py", line 47, in parse
    return compile(source, filename, mode, flags,
  File "<unknown>", line 1
    {'dataset':'news20'.'binary'}
                        ^
SyntaxError: invalid syntax

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/home/tlefort/condaenvs/phd/benchopt_benchmark_logreg_l1/bin/benchopt", line 33, in <module>
    sys.exit(load_entry_point('benchopt', 'console_scripts', 'benchopt')())
  File "/home/tlefort/.local/lib/python3.8/site-packages/click/core.py", line 1137, in __call__
    return self.main(*args, **kwargs)
  File "/home/tlefort/.local/lib/python3.8/site-packages/click/core.py", line 1062, in main
    rv = self.invoke(ctx)
  File "/home/tlefort/.local/lib/python3.8/site-packages/click/core.py", line 1668, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
  File "/home/tlefort/.local/lib/python3.8/site-packages/click/core.py", line 1404, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/home/tlefort/.local/lib/python3.8/site-packages/click/core.py", line 763, in invoke
    return __callback(*args, **kwargs)
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/cli/helpers.py", line 234, in info
    benchmark.validate_dataset_patterns(dataset_names)
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 122, in validate_dataset_patterns
    _validate_patterns(all_datasets, dataset_patterns, name_type='dataset')
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 588, in _validate_patterns
    matched = any([is_matched(name, [p]) for name in all_names])
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 588, in <listcomp>
    matched = any([is_matched(name, [p]) for name in all_names])
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 469, in is_matched
    name = _extract_options(name)[0]
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 517, in _extract_options
    result = _extract_parameters(match)
  File "/home/tlefort/Documents/phd/articles_and_others/sprint/benchOpt/benchopt/benchmark.py", line 577, in _extract_parameters
    raise ValueError(f"Invalid name '{original}', evaluated as {string}.")
ValueError: Invalid name 'dataset=news20.binary', evaluated as {'dataset':'news20'.'binary'}.
```
