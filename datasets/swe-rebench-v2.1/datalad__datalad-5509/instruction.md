git-config produces output that _parse_gitconfig_dump cannot handle
This is still a mystery, but this issue is about some aspect that might trigger a `get` failure that was reported to me. The environment is an HPC system with GPFS. Correction: the dataset is located in `/dev/shm/...` (tmpfs), while the user HOME is on GPFS.

```
$ datalad get -n inputs/ukb/sub-3192110
[WARNING] Skip unrecognized .gitmodule specification: rm: cannot remove '/p/home/users/.../.cache/git-annex/locales/97d8e8e226139eee06ab02ccdf2f4c84': Directory not empty=submodule.code/pipeline.path
[WARNING] Failed to get 'code/pipeline.path', skipping this submodule
```

The specific composition of this warning message makes me suspect that

```
        out = self.call_git(
            ['config', '-z', '-l', '--file', '.gitmodules'],
            read_only=True)
 ```

in `get.py:_parse_gitmodules()` produces output

```
rm: cannot remove '/p/home/users/.../.cache/git-annex/locales/97d8e8e226139eee06ab02ccdf2f4c84': Directory not empty
```

That `_parse_gitconfig_dump()` cannot handle, as a result gets mistaken for a misconfiguration, subsequently leading to critical submodule information being ignores, and ultimately failing the entire operation.

### Additional contract requirements

Unrelated leading output must not prevent valid configuration settings from being loaded. Repeated specifications of a setting must remain available through all-values configuration access. When a reported configuration source changes, reloading configuration must reflect the updated setting.
