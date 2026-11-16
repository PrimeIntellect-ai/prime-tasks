Sacred dislikes return type hint in config
I have a config function with a return type hint, like that:
```python
@ex.config
def config() -> None:
    """Experiment config."""
    ...
```
It seems that Sacred is trying to match this against an overly restrictive regex, and it gives an assert error:
```
Traceback (most recent call last):
  File "/home/carlos/git/pytorch_congealing/main.py", line 11, in <module>
    def config() -> None:
  File "/home/carlos/Programas/Utilidades/Lenguajes/miniconda3/envs/fda/lib/python3.7/site-packages/sacred/ingredient.py", line 162, in config
    self.configurations.append(ConfigScope(function))
  File "/home/carlos/Programas/Utilidades/Lenguajes/miniconda3/envs/fda/lib/python3.7/site-packages/sacred/config/config_scope.py", line 26, in __init__
    self._body_code = get_function_body_code(func)
  File "/home/carlos/Programas/Utilidades/Lenguajes/miniconda3/envs/fda/lib/python3.7/site-packages/sacred/config/config_scope.py", line 149, in get_function_body_code
    func_body, line_offset = get_function_body(func)
  File "/home/carlos/Programas/Utilidades/Lenguajes/miniconda3/envs/fda/lib/python3.7/site-packages/sacred/config/config_scope.py", line 107, in get_function_body
    assert defs
AssertionError
```
