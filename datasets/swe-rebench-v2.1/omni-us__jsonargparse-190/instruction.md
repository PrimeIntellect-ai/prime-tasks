`jsonargparse` is trying to deepcopy object in some case
<!-- If you like this project, please ⭐ star it https://github.com/omni-us/jsonargparse/ -->

## 🐛 Bug report

I really don't know what to write here, but I have attached code snippet with the errors.

### To reproduce

This fails:
```py
from pytorch_lightning.utilities.cli import LightningCLI
from pytorch_lightning import LightningModule
from torchvision.models.detection.retinanet import retinanet_resnet50_fpn


class RetinaNet(LightningModule):
    def __init__(self, **kwargs):
        super().__init__()
        if False:
            self.model = retinanet_resnet50_fpn(pretrained=pretrained, **kwargs)
        else:
            self.model = retinanet_resnet50_fpn(weights=None, weights_backbone="DEFAULT", **kwargs)

def cli_main():
    LightningCLI(RetinaNet, seed_everything_default=42)

if __name__ == '__main__':
    cli_main()
```

This does not:
```py
from pytorch_lightning.utilities.cli import LightningCLI
from pytorch_lightning import LightningModule
from torchvision.models.detection.retinanet import retinanet_resnet50_fpn


class RetinaNet(LightningModule):
    def __init__(self, **kwargs):
        super().__init__()
        if False:
            self.model = retinanet_resnet50_fpn(pretrained=pretrained)
        else:
            self.model = retinanet_resnet50_fpn(weights=None, weights_backbone="DEFAULT")

def cli_main():
    LightningCLI(RetinaNet, seed_everything_default=42)

if __name__ == '__main__':
    cli_main()
```

This does not:
```py
from pytorch_lightning.utilities.cli import LightningCLI
from pytorch_lightning import LightningModule
from torchvision.models.detection.retinanet import retinanet_resnet50_fpn


class RetinaNet(LightningModule):
    def __init__(self, **kwargs):
        super().__init__()
        self.model = retinanet_resnet50_fpn(weights=None, weights_backbone="DEFAULT", **kwargs)

def cli_main():
    LightningCLI(RetinaNet, seed_everything_default=42)

if __name__ == '__main__':
    cli_main()
```

error:
```console
File "/home/rohit/work/repos/lightning-bolts/build/temp.py", line 20, in cli_main
    LightningCLI(RetinaNet, seed_everything_default=42)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/pytorch_lightning/utilities/cli.py", line 157, in __init__
    super().__init__(*args, **kwargs)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/pytorch_lightning/cli.py", line 344, in __init__
    self.parse_arguments(self.parser, args)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/pytorch_lightning/cli.py", line 516, in parse_arguments
    self.config = parser.parse_args(args)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/jsonargparse/deprecated.py", line 112, in patched_parse
    cfg = parse_method(*args, _skip_check=_skip_check, **kwargs)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/jsonargparse/core.py", line 382, in parse_args
    parsed_cfg = self._parse_common(
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/jsonargparse/core.py", line 299, in _parse_common
    _ActionSubCommands.handle_subcommands(self, cfg, env=env, defaults=defaults, fail_no_subcommand=fail_no_subcommand)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/jsonargparse/actions.py", line 718, in handle_subcommands
    cfg[key] = subparser.merge_config(cfg.get(key, Namespace()), subnamespace)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/jsonargparse/core.py", line 1265, in merge_config
    cfg = cfg_to.clone()
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/site-packages/jsonargparse/namespace.py", line 271, in clone
    [HIDDEN]
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 172, in deepcopy
    y = _reconstruct(x, memo, *rv)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 270, in _reconstruct
    state = deepcopy(state, memo)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 146, in deepcopy
    y = copier(x, memo)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 230, in _deepcopy_dict
    y[deepcopy(key, memo)] = deepcopy(value, memo)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 172, in deepcopy
    y = _reconstruct(x, memo, *rv)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 270, in _reconstruct
    state = deepcopy(state, memo)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 146, in deepcopy
    y = copier(x, memo)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 230, in _deepcopy_dict
    y[deepcopy(key, memo)] = deepcopy(value, memo)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 172, in deepcopy
    y = _reconstruct(x, memo, *rv)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/copy.py", line 264, in _reconstruct
    y = func(*args)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/enum.py", line 384, in __call__
    return cls.__new__(cls, value)
  File "/home/rohit/miniconda3/envs/lit_bolts/lib/python3.9/enum.py", line 703, in __new__
    raise ve_exc
```

<!--
Please include a code snippet that reproduces the bug and the output that
running it gives. The following snippet templates might help:

1. Using the CLI function

```python
import jsonargparse

# Here define one or more functions or classes
def func1(param1: int, ...):
    ...

# Run the CLI providing the components
jsonargparse.CLI([func1, ...], error_handler=None)
```

2. Manually constructing a parser

```python
import jsonargparse

parser = jsonargparse.ArgumentParser(error_handler=None)
# Here add to the parser only argument(s) relevant to the problem

# If a yaml config is required, it can be included in the same snippet as follows:
import yaml
parser.add_argument('--config', action=jsonargparse.ActionConfigFile)
config = yaml.safe_dump({
    'key1': 'val1',
})

# Preferable that the command line arguments are given to the parse_args call
result = parser.parse_args([f'--config={config}', '--key2=val2', ...])

# If the problem is in the parsed result, print it to stdout
print(parser.dump(result))

# If the problem is in class instantiation
parser.instantiate_classes(result)
```
-->

### Expected behavior

<!-- Describe how the behavior or output of the reproduction snippet should be. -->

### Environment

<!-- Fill in the list below. -->

- jsonargparse version (e.g., 4.8.0): master
- Python version (e.g., 3.9): 3.9
- How jsonargparse was installed (e.g. `pip install jsonargparse[all]`):
- OS (e.g., Linux): Linux

### Additional contract requirements

- Cloning a configuration namespace during parsing must not fail solely because a leaf value cannot be deep-copied.
- Parsing must also complete for conditional model constructors that forward keyword arguments, including the reported LightningCLI-style construction.
