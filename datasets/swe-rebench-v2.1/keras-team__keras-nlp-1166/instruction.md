Add compute_output_shape method to WordPieceTokenizer
When we run Pretraining Transformer from Scratch guide with PyTorch and JAX backend, it raises

```

RuntimeError: Exception encountered when calling WordPieceTokenizer.call().

Could not automatically infer the output shape / dtype of 'word_piece_tokenizer_1' (of type WordPieceTokenizer). Either the `WordPieceTokenizer.call()` method is incorrect, or you need to implement the `WordPieceTokenizer.compute_output_spec() / compute_output_shape()` method. Error encountered:

'string'

Arguments received by WordPieceTokenizer.call():
  • args=('<KerasTensor shape=(None,), dtype=string, name=keras_tensor_59>',)
  • kwargs=<class 'inspect._empty'>
```

cc: @mattdangerw

### Additional contract requirements

- With `sequence_length` set, `WordPieceTokenizer` called on a symbolic string input such as `keras.Input(shape=(), dtype="string")` must succeed and produce a symbolic output whose shape is `(None, sequence_length)`.
- `compute_output_shape` on a `WordPieceTokenizer` given a string input shape `(batch,)` must return `(batch, sequence_length)`, and `(None,)` must map to `(None, sequence_length)`.
