Keras fails to train on custom generator (Torch backend)
Keras model would throw an error on training when using Torch backend and a custom (Python) data generator.

Steps to reproduce:
1) Define a model
2) Define a simple data generator that yields one batch of random data
3) Start training with `epoch=1` and `steps_per_epoch=1`
4) Get an `UnboundLocalError: local variable 'logs' referenced before assignment` suggesting that the training loop itself was skipped, and `epoch_iterator.enumerate_epoch()` has issues wrapping provided generator.

The same steps would work just fine with TF.

[Colab](https://colab.research.google.com/drive/1kOO9W-I2A3wrD3NOuwgH0_MPB-YFs7vr)

Edit: torch==2.3 seems to be incompatible with Keras, but it would have the same fail on 2.2 which should be supported
