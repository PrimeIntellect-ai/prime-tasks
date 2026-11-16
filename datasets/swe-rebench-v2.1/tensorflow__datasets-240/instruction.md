FeatureConnector serialization broken for byte strings
**Short description**
I am currently writing a custom FeatureConnector for RLE encoded segmentations. In order to save some storage space I am going to use the byte encoding of the numpy arrays and `tf.io.decode_raw` in order to decode the information (since tf.train.Example only supports int64 for integer data types). However, this line breaks the serialization of the byte string:
https://github.com/tensorflow/datasets/blob/c8c00f0843166775b44d3eba2e2171b44d2cb689/tensorflow_datasets/core/file_format_adapter.py#L397
One could argue, that this is a Tensorflow compat module bug, however, [HIDDEN]

**Environment information**
* Operating System: Ubuntu 18.04
* Python version: 3.6
* `tensorflow-datasets`/`tfds-nightly` version: tensorflow-datasets 1.0.1
* `tensorflow`/`tensorflow-gpu`/`tf-nightly`/`tf-nightly-gpu` version: tensorflow-gpu 1.13.1

**Reproduction instructions**

```python
import numpy as np
import tensorflow as tf
tf.enable_eager_execution()
arr = np.zeros((64, 64), dtype=np.uint8)
bytes = arr.tobytes()
print(len(bytes))  # 4096
v = np.asarray(bytes).flatten()  # tensorflow_datasets/core/file_format_adapter.py#390
bytes = tf.compat.as_bytes(v[0])  # tensorflow_datasets/core/file_format_adapter.py#397
print(len(bytes)) # 0
```

### Additional contract requirements

- Byte strings returned by a FeatureConnector must be serialized without losing or changing their byte contents.
