Retrying local training with external ID raises assertion
## Describe the bug

The assertion [here](https://github.com/caikit/caikit/blob/main/caikit/core/model_management/local_model_trainer.py#L313) in `LocalModelTrainer` can be triggered during a valid execution scenario where a training has failed and is being retried using the same external ID.

## Sample Code

```py
import aconfig
import alog
from caikit.core.toolkit.logging import configure
from caikit.core.model_management.local_model_trainer import LocalModelTrainer
from caikit.core import ModuleBase, module

log = alog.use_channel("REPRO")
configure()

@module("fail-train-once", "Module that will fail training once", "0.0.0")
class FailTrainOnce(ModuleBase):
    _calls = 0
    def __init__(self, val: int):
        self.val = val
    @classmethod
    def train(cls, arg: int):
        cls._calls = cls._calls + 1
        if cls._calls == 1:
            raise RuntimeError("Yikes!")
        return cls(arg)


trainer = LocalModelTrainer(aconfig.Config({}), "")
training_id = "my-training"

# First try should fail
try:
    log.info("First Try")
    model_future = trainer.train(FailTrainOnce, 42, external_training_id=training_id)
    model_future.load()
    raise AssertionError("Shouldn't get here")
except RuntimeError:
    # Second time should succeed
    log.info("Second Try")
    model_future = trainer.train(FailTrainOnce, 42, external_training_id=training_id)
    model = model_future.load()

assert model
```

## Expected behavior

The final `assert model` should pass because the first attempt reached a terminal state, so the second attempt is a retry

## Observed behavior

The call to `trainer.train` raises the linked `AssertionError` because the external ID is being reused

### Additional contract requirements

- If a training with the same external ID is still running, `trainer.train` must raise `ValueError` with a message matching `Cannot restart training.*`.
