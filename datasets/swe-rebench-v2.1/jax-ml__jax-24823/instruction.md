InconclusiveDimensionOperation: Symbolic dimension comparison 'b' < '2147483647' is inconclusive.
### Description

A simple code to reproduce:

```py
import jax
import jax.numpy as jnp
import jax.experimental.jax2tf as jax2tf
import tensorflow as tf


def f(a):
    return jnp.sort(a, axis=-1)


my_model = tf.Module()
my_model.f = tf.function(
    jax2tf.convert(
        lambda x: jax.vmap(jax.jacrev(jax.jit(f)))(x),
        with_gradient=True,
        polymorphic_shapes=["b, 3"],
    ),
    autograph=False,
    input_signature=[
        tf.TensorSpec([None, 3], tf.float32),
    ],
)
tf.saved_model.save(
    my_model,
    "test_model",
    options=tf.saved_model.SaveOptions(experimental_custom_gradients=True),
)

```


Output:
```
2024-11-05 17:04:52.450508: E external/local_xla/xla/stream_executor/cuda/cuda_fft.cc:477] Unable to register cuFFT factory: Attempting to register factory for plugin cuFFT when one has already been registered
WARNING: All log messages before absl::InitializeLog() is called are written to STDERR
E0000 00:00:1730844292.464466  861440 cuda_dnn.cc:8310] Unable to register cuDNN factory: Attempting to register factory for plugin cuDNN when one has already been registered
E0000 00:00:1730844292.468594  861440 cuda_blas.cc:1418] Unable to register cuBLAS factory: Attempting to register factory for plugin cuBLAS when one has already been registered
I0000 00:00:1730844294.252089  861440 gpu_device.cc:2022] Created device /job:localhost/replica:0/task:0/device:GPU:0 with 5038 MB memory:  -> device: 0, name: NVIDIA GeForce RTX 2080 SUPER, pci bus id: 0000:01:00.0, compute capability: 7.5
I0000 00:00:1730844294.252455  861440 gpu_device.cc:2022] Created device /job:localhost/replica:0/task:0/device:GPU:1 with 6795 MB memory:  -> device: 1, name: NVIDIA GeForce RTX 2080 SUPER, pci bus id: 0000:02:00.0, compute capability: 7.5
Traceback (most recent call last):
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 769, in _trace_gradient_functions
    def_function.function(custom_gradient).get_concrete_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 1251, in get_concrete_function
    concrete = self._get_concrete_function_garbage_collected(*args, **kwargs)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 1221, in _get_concrete_function_garbage_collected
    self._initialize(args, kwargs, add_initializers_to=initializers)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 696, in _initialize
    self._concrete_variable_creation_fn = tracing_compilation.trace_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/tracing_compilation.py", line 178, in trace_function
    concrete_function = _maybe_define_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/tracing_compilation.py", line 283, in _maybe_define_function
    concrete_function = _create_concrete_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/tracing_compilation.py", line 310, in _create_concrete_function
    traced_func_graph = func_graph_module.func_graph_from_py_func(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/framework/func_graph.py", line 1059, in func_graph_from_py_func
    func_outputs = python_func(*func_args, **func_kwargs)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 599, in wrapped_fn
    out = weak_wrapped_fn().__wrapped__(*args, **kwds)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/autograph_util.py", line 52, in autograph_handler
    raise e.ag_error_metadata.to_exception(e)
tensorflow.python.autograph.impl.api.StagingError: in user code:

    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/experimental/jax2tf/jax2tf.py", line 804, in grad_fn_tf
        in_cts_flat = convert(
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/experimental/jax2tf/jax2tf.py", line 437, in converted_fun_tf
        impl.before_conversion()
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/experimental/jax2tf/jax2tf.py", line 536, in before_conversion
        self.exported = _export.export_back_compat(
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/_export.py", line 635, in do_export
        traced = wrapped_fun_jax.trace(*args_specs, **kwargs_specs)
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/_export.py", line 1296, in fun_vjp_jax
        _, pullback_jax = jax.vjp(primal_fun if flat_primal_fun else flattened_primal_fun_jax,
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/_export.py", line 1290, in flattened_primal_fun_jax
        res = primal_fun(*args, **kwargs)
    File "/home/jz748/codes/deepmd-kit/test_xla/test.py", line 12, in <lambda>
        my_model.f = tf.function(jax2tf.convert(lambda x: jax.vmap(jax.jacrev(jax.jit(f)))(x), with_gradient=True, polymorphic_shapes=["b, 3"]),
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/shape_poly.py", line 857, in __lt__
        return not _geq_decision(self, other, lambda: f"'{self}' < '{other}'")
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/shape_poly.py", line 1170, in _geq_decision
        raise InconclusiveDimensionOperation(

    InconclusiveDimensionOperation: Symbolic dimension comparison 'b' < '2147483647' is inconclusive.
    This error arises for comparison operations with shapes that
    are non-constant, and the result of the operation cannot be represented as
    a boolean value for all values of the symbolic dimensions involved.

    Please see https://jax.readthedocs.io/en/latest/export/shape_poly.html#comparison-of-symbolic-dimensions-is-partially-supported
    for more details.


Traceback (most recent call last):
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 769, in _trace_gradient_functions
    def_function.function(custom_gradient).get_concrete_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 1251, in get_concrete_function
    concrete = self._get_concrete_function_garbage_collected(*args, **kwargs)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 1221, in _get_concrete_function_garbage_collected
    self._initialize(args, kwargs, add_initializers_to=initializers)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 696, in _initialize
    self._concrete_variable_creation_fn = tracing_compilation.trace_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/tracing_compilation.py", line 178, in trace_function
    concrete_function = _maybe_define_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/tracing_compilation.py", line 283, in _maybe_define_function
    concrete_function = _create_concrete_function(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/tracing_compilation.py", line 310, in _create_concrete_function
    traced_func_graph = func_graph_module.func_graph_from_py_func(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/framework/func_graph.py", line 1059, in func_graph_from_py_func
    func_outputs = python_func(*func_args, **func_kwargs)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/polymorphic_function.py", line 599, in wrapped_fn
    out = weak_wrapped_fn().__wrapped__(*args, **kwds)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/eager/polymorphic_function/autograph_util.py", line 52, in autograph_handler
    raise e.ag_error_metadata.to_exception(e)
tensorflow.python.autograph.impl.api.StagingError: in user code:

    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/experimental/jax2tf/jax2tf.py", line 804, in grad_fn_tf
        in_cts_flat = convert(
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/experimental/jax2tf/jax2tf.py", line 437, in converted_fun_tf
        impl.before_conversion()
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/experimental/jax2tf/jax2tf.py", line 536, in before_conversion
        self.exported = _export.export_back_compat(
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/_export.py", line 635, in do_export
        traced = wrapped_fun_jax.trace(*args_specs, **kwargs_specs)
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/_export.py", line 1296, in fun_vjp_jax
        _, pullback_jax = jax.vjp(primal_fun if flat_primal_fun else flattened_primal_fun_jax,
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/_export.py", line 1290, in flattened_primal_fun_jax
        res = primal_fun(*args, **kwargs)
    File "/home/jz748/codes/deepmd-kit/test_xla/test.py", line 12, in <lambda>
        my_model.f = tf.function(jax2tf.convert(lambda x: jax.vmap(jax.jacrev(jax.jit(f)))(x), with_gradient=True, polymorphic_shapes=["b, 3"]),
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/shape_poly.py", line 857, in __lt__
        return not _geq_decision(self, other, lambda: f"'{self}' < '{other}'")
    File "/home/jz748/anaconda3/lib/python3.10/site-packages/jax/_src/export/shape_poly.py", line 1170, in _geq_decision
        raise InconclusiveDimensionOperation(

    InconclusiveDimensionOperation: Symbolic dimension comparison 'b' < '2147483647' is inconclusive.
    This error arises for comparison operations with shapes that
    are non-constant, and the result of the operation cannot be represented as
    a boolean value for all values of the symbolic dimensions involved.

    Please see https://jax.readthedocs.io/en/latest/export/shape_poly.html#comparison-of-symbolic-dimensions-is-partially-supported
    for more details.



The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/home/jz748/codes/deepmd-kit/test_xla/test.py", line 15, in <module>
    tf.saved_model.save(my_model, "test_model",
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 1432, in save
    save_and_return_nodes(obj, export_dir, signatures, options)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 1467, in save_and_return_nodes
    _build_meta_graph(obj, signatures, options, meta_graph_def))
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 1682, in _build_meta_graph
    return _build_meta_graph_impl(obj, signatures, options, meta_graph_def)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 1606, in _build_meta_graph_impl
    asset_info, exported_graph = _fill_meta_graph_def(
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 974, in _fill_meta_graph_def
    _trace_gradient_functions(exported_graph, saveable_view)
  File "/home/jz748/anaconda3/lib/python3.10/site-packages/tensorflow/python/saved_model/save.py", line 773, in _trace_gradient_functions
    raise ValueError(
ValueError: Error when tracing gradients for SavedModel.

Check the error log to see the error that was raised when converting a gradient function to a concrete function. You may need to update the custom gradient, or disable saving gradients with the option tf.saved_model.SaveOptions(experimental_custom_gradients=False).
        Problematic op name: IdentityN
        Gradient inputs: (<tf.Tensor 'XlaCallModule:0' shape=(None, 3, 3) dtype=float32>, <tf.Tensor 'jax2tf_arg_0:0' shape=(None, 3) dtype=float32>)
```


### System info (python version, jaxlib version, accelerator, etc.)

```
jax:    0.4.35
jaxlib: 0.4.35
numpy:  1.26.4
python: 3.10.13 | packaged by conda-forge | (main, Dec 23 2023, 15:36:39) [GCC 12.3.0]
device info: NVIDIA GeForce RTX 2080 SUPER-2, 2 local devices"
process_count: 1
platform: uname_result(system='Linux', node='localhost.localdomain', release='6.8.9-100.fc38.x86_64', version='#1 SMP PREEMPT_DYNAMIC Thu May  2 18:50:49 UTC 2024', machine='x86_64')


$ nvidia-smi
Tue Nov  5 17:06:50 2024
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 550.78                 Driver Version: 550.78         CUDA Version: 12.4     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA GeForce RTX 2080 ...    Off |   00000000:01:00.0  On |                  N/A |
| 18%   50C    P2             47W /  250W |    1660MiB /   8192MiB |     27%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
|   1  NVIDIA GeForce RTX 2080 ...    Off |   00000000:02:00.0 Off |                  N/A |
| 18%   38C    P2             27W /  250W |     123MiB /   8192MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+

+-----------------------------------------------------------------------------------------+
| Processes:                                                                              |
|  GPU   GI   CI        PID   Type   Process name                              GPU Memory |
|        ID   ID                                                               Usage      |
|=========================================================================================|
|    0   N/A  N/A      1743      G   /usr/libexec/Xorg                             780MiB |
|    0   N/A  N/A      2813      G   /usr/bin/gnome-shell                           63MiB |
|    0   N/A  N/A      3523      G   ...AAAAAAAACAAAAAAAAAA= --shared-files         21MiB |
|    0   N/A  N/A      4103      G   /usr/libexec/xdg-desktop-portal-gnome          65MiB |
|    0   N/A  N/A      4226      G   ...seed-version=20241025-050055.764000         34MiB |
|    0   N/A  N/A      5786      G   ...erProcess --variations-seed-version        294MiB |
|    0   N/A  N/A    862432      C   python                                        118MiB |
|    0   N/A  N/A   1334593      G   /usr/bin/gnome-text-editor                     11MiB |
|    0   N/A  N/A   1754958      G   /usr/lib64/firefox/firefox                    175MiB |
|    0   N/A  N/A   2612107      G   /usr/bin/file-roller                           31MiB |
|    1   N/A  N/A    862432      C   python                                        118MiB |
+-----------------------------------------------------------------------------------------+
```
