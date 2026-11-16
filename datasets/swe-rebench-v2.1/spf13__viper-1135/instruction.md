MergeConfig fails when a target key is nil instead of unset
**Expected behavior (what you expected to happen)**:
I am merging a config file on top of existing configuration. So some of the keys, like a slice, may be nil instead of unset. I expect that merging a populated key into a configuration where that key is nil results in using the populated value.

**Actual behavior (what actually happened)**:
I see a log message from jww about the source and destination types not matching (because the type of the target is nil) and then the key is skipped.

```
ERROR 2021/05/12 17:26:29 svType != tvType; key=storage, st=[]interface {}, tt=<nil>, sv=[map[config:map[env:MY_ENV_VAR] name:stuff plugin:myplugin]], tv=<nil>
```

The failure is occurring on these lines is https://github.com/spf13/viper/blob/36be6bf91f8c02e8fd53f87205ad230706a3eea9/viper.go#L1829-L1834


**Repl.it link**:
None

**Code reproducing the issue**:

This was easier to reproduce with a single change to the viper test `TestMergeConfig` by setting universe to `null`, instead of omitting it. That causes the test to fail.

https://github.com/spf13/viper/blob/36be6bf91f8c02e8fd53f87205ad230706a3eea9/viper_test.go#L1693-L1703

```
var yamlMergeExampleTgt = []byte(`
hello:
    pop: 37890
    largenum: 765432101234567
    num2pow63: 9223372036854775808
    universe: null
    world:
    - us
    - uk
    - fr
    - de
`)
```

**Environment**:
- Viper version: tip of master 36be6bf
- Config source: files
- File format: any

**Anything else we should know?**:
