Question: Best practice for direct variable initialization
Some layers require explicit initialization of the whole variable tensor. What is the best practice for doing this? Currently, I am passing the tensor as the `value` argument to `keras.initializers.Constant`, but this seems like a hacky work-around, since the docs never explicitly mention using `Constant` with non-floats, and the value is also unnecessarily multiplied with a tensor of ones on initializer call.

For reference, I am doing something like this (there is no built-in initializer for rolling indices):

```py3
class SomeLayer(keras.Layer):
    def build(self, input_shape):
        indices = keras.ops.roll(keras.ops.arange(input_shape[-1]), shift=input_shape[-1] // 2)

        self.indices = self.add_variable(shape=input_shape[-1], initializer=keras.initializers.Constant(indices), trainable=False)
```

### Additional contract requirements

A precomputed backend tensor can be used directly as an initializer without wrapping it in `Constant`. This includes integer-valued tensors, such as rolling indices.
