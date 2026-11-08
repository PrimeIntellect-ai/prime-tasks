[Bug] handle yaml file with dot in the name
# 🐛 Bug

<!-- A clear and concise description of what the bug is. -->
When creating yaml file that has dot in the base name, `config_loader.py` erroneously misses the `.yaml` extension which results in a `hydra.errors.MissingConfigException`.

## To reproduce
configuration groups:
```
├── conf
│   └── lr
│       ├── 0.1.yaml
│       └── 0.01.yaml
└── my_app.py
```
with minimum `my_app.py` setup same as in the tutorial
```
python my_app.py lr=0.1
```
Traceback:
```
Traceback (most recent call last):
  File "app.py", line 9, in <module>
    app()
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/main.py", line 24, in decorated_main
    strict=strict,
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/utils.py", line 56, in run_hydra
    hydra.run(overrides=args.overrides)
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/hydra.py", line 103, in run
    cfg = self._load_config(overrides)
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/hydra.py", line 345, in _load_config
    cfg = self.config_loader.load_configuration(overrides)
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/config_loader.py", line 56, in load_configuration
    cfg = self._merge_defaults(hydra_cfg, defaults, split_at)
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/config_loader.py", line 395, in _merge_defaults
    cfg = merge_defaults(cfg, user_list)
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/config_loader.py", line 374, in merge_defaults
    required=not is_optional,
  File "/home/yjxiao/miniconda3/lib/python3.7/site-packages/hydra/_internal/config_loader.py", line 301, in _merge_config
    raise MissingConfigException(msg, new_cfg, options)
hydra.errors.MissingConfigException: Could not load lr/0.1, available options:
lr:
	0.01
	0.1
```
## Questions
- [HIDDEN] Would this cause any unwanted behavior with other features?
- Is it generally not advisable to name config files with, say, float values? Are there better ways to incorporate float values in the config?

### Additional contract requirements

- Selecting a YAML config whose base name contains a dot, without specifying the `.yaml` suffix, must load the corresponding config rather than raise `MissingConfigException`.
