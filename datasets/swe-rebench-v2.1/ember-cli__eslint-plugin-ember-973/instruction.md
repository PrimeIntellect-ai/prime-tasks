New rule: Lint against `tryInvoke`
There is an open RFC to deprecate `tryInvoke`. We should also create a new lint rule against future usage of `tryInvoke`

RFC to deprecate `tryInvoke`:
https://github.com/emberjs/rfcs/pull/673

### Additional contract requirements

- The rule must be available through the plugin's public rule registry under the `no-try-invoke` key so consumers can enable it.
