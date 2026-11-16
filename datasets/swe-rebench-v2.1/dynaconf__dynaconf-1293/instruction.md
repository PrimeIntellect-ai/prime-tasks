[bug] list command must error for not found key
```bash
# /venv/bin/dynaconf list -k "D" --json
Key not found
# echo $?
0
```

Expected: `1` retcode

---

Open for discussion:

- Should retcode be `1`
- Should return empty json `{}`

?
