Cannot call AttentionLayer with symbolic tensors and return_attention_scores=True in Keras 3
In Keras 3 I cannot call the call method of AttentionLayer (or other attention layer classes) with a symbolic KerasTensor input and return_attention_scores=True.

I am using Python 3.12.1 and Keras 3.6.0

```
>>> in1 = keras.Input(shape=(10, 7))
>>> in2 = keras.Input(shape=(8, 7))
>>> attLayer = keras.layers.Attention()
>>> out1, out2 = attLayer([in1, in2], return_attention_scores=True)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "<venv_root>/lib/python3.12/site-packages/keras/src/backend/common/keras_tensor.py", line 167, in __iter__
    raise NotImplementedError(
NotImplementedError: Iterating over a symbolic KerasTensor is not supported.
```

The layer call method works when replacing the symbolic inputs with np.ndarray inputs.

### Additional contract requirements

`keras.layers.AdditiveAttention` must also accept symbolic KerasTensor query and value inputs with `return_attention_scores=True` and return both the attended output and attention scores as symbolic tensors with the corresponding query and value dimensions.
