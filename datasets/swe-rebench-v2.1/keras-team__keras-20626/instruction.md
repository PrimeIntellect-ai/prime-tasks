Normalization layer fails to broadcast scalar mean and variance
Normalization layer errors out for scalar mean and variance arguments. The documentation states that these arguments will be broadcast to the necessary size and the examples include scalars, but instead [HIDDEN].

I'm using Python 3.12.1 and Keras 3.6.0.

```
>>> in1 = keras.Input(shape=(16, 16, 3))
>>> normLayer = keras.layers.Normalization(mean=0.1, variance=0.05)
>>> out1 = normLayer(in1)
I tensorflow/core/framework/local_rendezvous.cc:405] Local rendezvous is aborting with status: INVALID_ARGUMENT: Input to reshape is a tensor with 1 values, but the requested shape has 3
```
