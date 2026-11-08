[Bug] --cfg not working
# 🐛 Bug

when running `python main.py --cfg hydra`


** Stack trace/error message **
```
Traceback (most recent call last):
  File "main.py", line 576, in <module>
    main()
  File "/private/home/yannd/.conda/envs/assl/lib/python3.7/site-packages/hydra/main.py", line 24, in decorated_main
    strict=strict,
  File "/private/home/yannd/.conda/envs/assl/lib/python3.7/site-packages/hydra/_internal/utils.py", line 183, in run_hydra
    hydra.show_cfg(overrides=args.overrides, cfg_type=args.cfg)
  File "/private/home/yannd/.conda/envs/assl/lib/python3.7/site-packages/hydra/_internal/hydra.py", line 116, in show_cfg
    cfg = self.compose_config(overrides, with_log_configuration=True)
TypeError: compose_config() missing 1 required positional argument: 'overrides'
```

## System information
- Hydra 0.11
- Python : 3.7
