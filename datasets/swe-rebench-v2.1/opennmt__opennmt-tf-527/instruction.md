ValueError in guided alignment loss during training
Keras losses throw an exception when they are used within a distribution strategy scope and the reduction mode is unset.

```
ValueError: Please use `tf.keras.losses.Reduction.SUM` or `tf.keras.losses.Reduction.NONE` for loss reduction when losses are used with `tf.distribute.Strategy` outside of the built-in training loops. You can implement `tf.keras.losses.Reduction.SUM_OVER_BATCH_SIZE` using global batch size like:
```

### Additional contract requirements

The guided alignment loss is computed by the public function
`guided_alignment_cost(attention_probs, gold_alignment, sequence_length=None, cost_type="ce", weight=1.0)`
in module `opennmt.utils.losses`.

- `attention_probs` and `gold_alignment` are float tensors of shape `[batch, target_len, source_len]`.
- `sequence_length` is an optional integer tensor of shape `[batch]` giving the number of valid target positions for each sequence.
- `cost_type` selects the loss: `"ce"` for categorical cross-entropy and `"mse"` for mean-squared error. Any other value raises `ValueError`.
- The returned value is a scalar tensor.
- The loss can be evaluated inside a `tf.distribute.Strategy` scope.
- When `sequence_length` is provided, target positions beyond each sequence length do not contribute to the loss and the loss is normalized by the sum of the sequence lengths.
- `weight` is a scalar multiplier applied to the loss (default `1.0`).
