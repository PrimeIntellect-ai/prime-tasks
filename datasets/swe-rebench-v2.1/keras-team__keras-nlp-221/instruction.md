Add a start and end token packer layer
```
class StartEndPacker(keras.layers.Layer):
    """Adds start and end tokens to a sequence and pads to a fixed length.

    If inputs are batched, input should be a `tf.RaggedTensor`s with shape
    `[batch_size, None]` and will be packed and converted to a dense tensor with
    shape `[batch_size, sequence_length]`.
    If inputs are unbatched, inputs should be dense rank-1 tensors of any shape,
    and will be packed to shape `[sequence_length]`.

    Args:
        sequence_length: The desired output length.
        start_value: The id or token that is to be placed at the start of each
            sequence. The dtype must mach the dtype of the input tensors to
            the layer. If None, no start value will be added.
        end_value: The id or token that is to be placed at the end of each
            input segment. The dtype must mach the dtype of the input tensors to
            the layer. If None, no end value will be added.
        pad_value: The id or token that is to be placed into the unused
            positions after the last segment in the sequence.
    """
    def __init__(
        self,
        sequence_length,
        start_value=None,
        end_value=None,
        pad_value=None,
    )
```
