class instantiation with multiple parameters
Hello, I have a question on how I can instantiate a class that requires multiple parameters that determined during run time only?
I followed the example on [Optimizer](https://jsonargparse.readthedocs.io/en/v4.24.0/#callable-type) but can't figure out how I can expand it to multiple parameters:

```python
# Example from the website
class Optimizer:
    def __init__(self, params: Iterable):
        self.params = params


class SGD(Optimizer):
    def __init__(self, params: Iterable, lr: float):
        super().__init__(params)
        self.lr = lr


if __name__ == '__main__':
    value = {
        "class_path": "SGD",
        "init_args": {
            "lr": 0.01,
        },
    }

    parser = ArgumentParser()
    parser.add_argument("--optimizer", type=Callable[[Iterable], Optimizer])
    cfg = parser.parse_args(["--optimizer", str(value)])
    init = parser.instantiate_classes(cfg)
    optimizer = init.optimizer([1, 2, 3])
```

Let's say I want to add one more parameter to `SGD(params, weight, lr)`. How will the flow change?

```python
class SGD(Optimizer):
    def __init__(self, params: Iterable, weight: float, lr: float):
...
parser.add_argument("--optimizer", type=Callable[[Iterable, float], Optimizer])
```
gives the following error:
```
usage: example.py [-h] [--optimizer OPTIMIZER]
example.py: error: Parser key "optimizer":
  Expected a dot import path string: SGD
```
Setting `class_path` to `__main__.SGD` produces another error:
```
usage: example.py [-h] [--optimizer OPTIMIZER]
example.py: error: Parser key "optimizer":
  Type typing.Callable[[typing.Iterable, float], __main__.Optimizer] expects a function or a callable class: Expected '__main__.SGD' to be a class that instantiates into callable or a subclass of False.. Got value: Namespace(class_path='__main__.SGD', init_args=Namespace(lr=0.01))

```
