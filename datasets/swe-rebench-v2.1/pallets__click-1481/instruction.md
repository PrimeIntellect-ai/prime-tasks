Friendly __repr__ for Command
```python
(Pdb) pp cmd
<click.core.Command object at 0x7ff869ef1550>
(Pdb) pp cmd.name
'run-gunicorn'
```
What do you think of showing the command name in the `__repr__` string, for friendlier debugging? Could be a good beginner-friendly issue!
