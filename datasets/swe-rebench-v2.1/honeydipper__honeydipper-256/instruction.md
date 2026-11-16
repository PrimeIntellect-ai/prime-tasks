configcheck for contexts exiting 0 on errors
```
730f75d634de:~/project# /opt/honeydipper/drivers/builtin/honeydipper configcheck

Found error in Contexts
─────────────────────────────────────────────────────────────
context(_default): workflow `spanner_asdf` not defined
context(_default): workflow `spanner_restore` not defined
730f75d634de:~/project# echo $?
0
```

### Additional contract requirements

- When context errors are found, `configcheck` must return exit status `1`.
