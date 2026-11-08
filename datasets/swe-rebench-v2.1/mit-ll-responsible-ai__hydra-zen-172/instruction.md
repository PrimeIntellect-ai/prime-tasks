Bypassing omegaconf issue that leads to unexpected results/bug
See https://github.com/omry/omegaconf/issues/830 for the description of the bug.

In short, instantiation "ignores" child class' default-factory-field in favor of the parent's value (unless that value is specifically `MISSING`)

```python
>>> A = make_config(x=1)
>>> B = make_config(x=[1, 2], bases=(A,))  # must be a mutable value to trigger the bug
>>> instantiate(B)
{'x': 1}
```

Given that hydra-zen users are particularly heavy users of dataclasses who do not have to deal with the cumbersom nature of manually creating default-factories (since we create the default-factories for them), they are much more likely to be affected by this bug than the average Hydra user, I suspect.

Thus it is pressing that we address this on the hydra-zen end either by: hard-pinning the minimum version of `omegaconf` to require the patched version, or, "detecting" this scenario ourselves and use a workaround. E.g., @jgbos pointed out that we can attempt to detect and remedy this issue for users by effectively doing the following "under the hood":

[HIDDEN]

this remedies the issue :

```python
>>> A = make_config(x=1)
[HIDDEN]
>>> instantiate(B)
{'x': [1, 2]}
```

### Additional contract requirements

- Add a public exception type `HydraZenValidationError` in module `hydra_zen.errors`. `hydrated_dataclass` raises it when the config it decorates would not instantiate correctly because of the omegaconf #830 scenario: a default-factory field that collides with a non-factory field inherited from a parent.
- Add a public boolean flag `PATCH_OMEGACONF_830` in module `hydra_zen.structured_configs._utils` indicating whether the installed OmegaConf version exhibits issue #830.
- `make_config` accepts a `bases` tuple of parent config types, and `builds` accepts a `builds_bases` tuple of parent config types. This applies to both the regular and the partial (`zen_partial=True`) variants of `builds`. `hydrated_dataclass` supports inheritance by subclassing a parent config.
- `hydra_zen.ZenField(hint, default, name)` and `hydra_zen.mutable_value(value)` are public helpers for specifying a field and a mutable default, respectively.
- For child configs created with `make_config` or `builds`, when a mutable child field supplied by a default factory overrides an inherited non-factory field, instantiating the child config must yield the child's field value rather than the parent's value.
