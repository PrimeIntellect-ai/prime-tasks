detox init removes final newline in package.json
Running `detox init -r mocha` outputs

```
[...]
detox[47771] INFO:  [init.js] detox-init Patched ./package.json with commands:
detox[47771] INFO:  [init.js] detox-init _.set(packageJson, ['detox', 'test-runner'], "mocha")
detox[47771] INFO:  [init.js] detox-init _.set(packageJson, ['detox', 'specs'], "")
```

As a side effect, it also **removes the newline character** from the last line in `package.json`.

This results warnings like `No newline at end of file`, and malfunctioning of certain tools due to the fact that the file is strictly speaking no longer a valid text file according to [POSIX standards](http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap03.html) (3.206 / 3.403).

Also see: https://stackoverflow.com/questions/729692/why-should-text-files-end-with-a-newline

### Additional contract requirements

- After `detox init` rewrites `package.json`, the file ends with a newline character, and the rewritten file still contains the original fields together with the detox test-runner setting.
