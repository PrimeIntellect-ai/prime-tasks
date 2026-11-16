[HIDDEN]
Hello,

I am using the `@zen` decorator in my project, and using its `pre_call` arg to modify my config. I am trying to modify the unresolved config, but `pre_call` gets the config after `OmegaConf.resolve(cfg)` has been run.
https://github.com/mit-ll-responsible-ai/hydra-zen/blob/796d8ac7c87c5ad245eb739cd27b81cf62eb19ca/src/hydra_zen/wrapper/_implementations.py#L336

Can [HIDDEN] to allow for more flexibility?

### Additional contract requirements

- `zen` accepts a keyword-only parameter `resolve_pre_call: bool` that defaults to `True`.
- When `resolve_pre_call` is `True`, interpolated fields in the config are resolved before `pre_call` runs. When it is `False`, `pre_call` can inspect and modify the config while its interpolated fields remain unresolved; those fields are resolved after `pre_call` runs.
