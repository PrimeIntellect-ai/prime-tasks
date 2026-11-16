Add a sinusoidal embedding layer
Along with a learned positional embedding (https://github.com/keras-team/keras-nlp/issues/23), we should add a fixed sin/cos embedding as described in [Attention is all you need](https://arxiv.org/pdf/1706.03762.pdf).

### Additional contract requirements

- The fixed sin/cos positional encoding is exposed as `keras_nlp.layers.SinePositionEncoding`. It can be constructed with no arguments; its default `max_wavelength` is 10000.
- Calling the layer on an input whose last two dimensions are sequence length and feature size returns the sinusoidal encoding for each position and feature: for position `p` and feature index `i`, even `i` gives `sin(p / 10000^(i/d))` and odd `i` gives `cos(p / 10000^((i-1)/d))`, where `d` is the feature size.
- The returned encoding can be added to the input, with the result having the same shape as the input (batch dimensions broadcast).
- The encoding is fixed: it is not trainable and does not change when the layer is trained.
