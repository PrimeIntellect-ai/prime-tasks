`Normalizer`: `float` precision
Hey there,

as we already had [issues](https://github.com/CuyZ/Valinor/issues/360) in valinor regarding `float` and `int` strict comparison, I wanted to bring this topic up.

I am not sure how different languages handle this, but I would assume that `int` can be a `float` as well, however, to prevent that, we sometimes used `JSON_PRESERVE_ZERO_FRACTION`.

Valinors `JsonNormalizer` is just casting floats to string which drops the zero fraction and converts floats to `int` in case they do not have decimals.

Should we either add a way to enable this behavior or is this ignored on purpose?
Current workaround is to use the array normalizer and `json_encode` on our own in combination with `JSON_PRESERVE_ZERO_FRACTION`.

### Additional contract requirements

The JSON normalizer must provide `withOptions(int $options)` as an opt-in way to preserve the zero fractional part of integral-valued floats using `JSON_PRESERVE_ZERO_FRACTION`. Without opting in, JSON normalization must continue omitting the zero fractional part of integral-valued floats. For example, an input value of `1.0` can be emitted as `1.0` rather than `1`, so JSON consumers can distinguish it from an integer. Enabling JSON encoding options must not disable the normalizer's existing behavior of throwing when encoding fails.
