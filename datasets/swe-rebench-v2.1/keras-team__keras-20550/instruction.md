Cloning of Sequential models w. input_tensors argument fails
Cloning a Sequential models layers fails if using the input_tensors argument.

Minimum reproducible example:

```
import keras

model = keras.models.Sequential()
model.add(keras.layers.Input(shape=(7, 3)))
model.add(keras.layers.Conv1D(2, 2, padding="same"))

input_tensor = model.inputs[0]
new_model = keras.models.clone_model(model, input_tensors=input_tensor)
```

Traceback:
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/workspaces/keras/keras/src/models/cloning.py", line 159, in clone_model
    return _clone_sequential_model(
  File "/workspaces/keras/keras/src/models/cloning.py", line 301, in _clone_sequential_model
    if input_tensors:
  File "/workspaces/keras/keras/src/backend/common/keras_tensor.py", line 172, in __bool__
    raise TypeError("A symbolic KerasTensor cannot be used as a boolean.")
TypeError: A symbolic KerasTensor cannot be used as a boolean.
```

Still fails even after manually changing `if input_tensors:` to `if input_tensors is not None:` in keras/src/models/cloning.py:
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/workspaces/keras/keras/src/models/cloning.py", line 159, in clone_model
    return _clone_sequential_model(
  File "/workspaces/keras/keras/src/models/cloning.py", line 313, in _clone_sequential_model
    inputs = Input(tensor=input_tensors, name=input_name)
  File "/workspaces/keras/keras/src/layers/core/input_layer.py", line 154, in Input
    layer = InputLayer(
  File "/workspaces/keras/keras/src/layers/core/input_layer.py", line 44, in __init__
    raise ValueError("You must pass a `shape` argument.")
ValueError: You must pass a `shape` argument.
```

### Additional contract requirements

When a symbolic tensor is supplied through `input_tensors`, the cloned model must use that exact tensor as its input, while preserving the source model's input and output structures.
