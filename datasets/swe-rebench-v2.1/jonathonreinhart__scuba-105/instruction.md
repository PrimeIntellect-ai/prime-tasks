Scuba can mangle certain script constructs
`shell_quote_cmd()` seems to be making bad decisions:

`.scuba.yml`:
```yaml
image: foo
aliases:
  foo:
    script:
      - cd somewhere && ./run.sh
```

Output `/.scuba/command.sh`:
```sh
cd somewhere '&&' ./run.sh
```

Bash doesn't like the `'&&'` and then ignores the rest of the line.
