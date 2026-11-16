Add shell completion for --version flag
This proposal is to add shell completion for the `--version` flag.  As an example
```
helm show all stable/fluentd --version <TAB>
helm pull stable/fluentd --version <TAB>
helm install myfluentd stable/fluentd --version <TAB>
helm upgrade myfluentd stable/fluentd --version <TAB>
```
would suggest
```
1.0.0   1.10.0  1.2.0   1.4.0   1.5.1   1.7.0   1.9.1   2.0.1   2.0.3   2.2.0   2.3.0   2.3.2   2.4.0
1.1.0   1.10.1  1.3.0   1.5.0   1.6.0   1.9.0   2.0.0   2.0.2   2.1.3   2.2.1   2.3.1   2.3.3   2.4.1
```
This improvement is not as much about saving users some typing as it is about helping users figure out which versions are available.

### Additional contract requirements

When a valid `<repo>/<chart>` reference is followed by `--version` completion, suggest the available versions for that chart. If the user has already typed part of a version, suggest only available versions that begin with that text. The order of suggestions is not significant.
