Error when trying to measure reserved memory with lithops
I tried to measure the reserved memory with lithops (set up to run on Google Cloud Functions) and this happened:

```python
IPython 8.13.2 -- An enhanced Interactive Python. Type '?' for help.

In [1]: from cubed import measure_reserved_memory

In [2]: from cubed.runtime.executors.lithops import LithopsDagExecutor

In [3]: import cubed

In [4]: measure_reserved_memory(LithopsDagExecutor())
2023-05-24 17:59:58,539 [INFO] config.py:134 -- Lithops v2.9.0
2023-05-24 17:59:58,878 [INFO] gcp_storage.py:45 -- Google Cloud Storage client created
2023-05-24 17:59:58,990 [INFO] gcp_functions.py:68 -- Google Cloud Functions client created - Region: us-east1 - Project: pangeo-forge-4967
2023-05-24 17:59:58,990 [INFO] invokers.py:108 -- ExecutorID 646b95-0 | JobID M000 - Selected Runtime: default-runtime-v39 - 256MB
2023-05-24 17:59:59,545 [INFO] invokers.py:172 -- ExecutorID 646b95-0 | JobID M000 - Starting function invocation: <lambda>() - Total: 1 activations
2023-05-24 17:59:59,548 [INFO] invokers.py:208 -- ExecutorID 646b95-0 | JobID M000 - View execution logs at /tmp/lithops-tom/logs/646b95-0-M000.log
2023-05-24 17:59:59,549 [INFO] wait.py:97 -- ExecutorID 646b95-0 - Waiting for -1% of 1 function activations to complete
2023-05-24 18:00:02,556 [WARNING] future.py:257 -- ExecutorID 646b95-0 | JobID M000 - There was an exception - Activation ID: 405f3d1778b148a5be84a124639af17b
2023-05-24 18:00:02,557 [WARNING] future.py:260 -- Exception: ModuleNotFoundError - No module named 'cubed'
2023-05-24 18:00:02,557 [INFO] invokers.py:108 -- ExecutorID 646b95-0 | JobID M001 - Selected Runtime: default-runtime-v39 - 256MB
2023-05-24 18:00:02,563 [INFO] invokers.py:172 -- ExecutorID 646b95-0 | JobID M001 - Starting function invocation: <lambda>() - Total: 1 activations
2023-05-24 18:00:02,563 [INFO] invokers.py:208 -- ExecutorID 646b95-0 | JobID M001 - View execution logs at /tmp/lithops-tom/logs/646b95-0-M001.log
2023-05-24 18:00:02,564 [INFO] wait.py:97 -- ExecutorID 646b95-0 - Waiting for -1% of 1 function activations to complete
2023-05-24 18:00:05,572 [WARNING] future.py:257 -- ExecutorID 646b95-0 | JobID M001 - There was an exception - Activation ID: ee879e0e92b242c4b8c57813a5376753
2023-05-24 18:00:05,572 [WARNING] future.py:260 -- Exception: ModuleNotFoundError - No module named 'cubed'
2023-05-24 18:00:05,573 [INFO] invokers.py:108 -- ExecutorID 646b95-0 | JobID M002 - Selected Runtime: default-runtime-v39 - 256MB
2023-05-24 18:00:05,577 [INFO] invokers.py:172 -- ExecutorID 646b95-0 | JobID M002 - Starting function invocation: <lambda>() - Total: 1 activations
2023-05-24 18:00:05,577 [INFO] invokers.py:208 -- ExecutorID 646b95-0 | JobID M002 - View execution logs at /tmp/lithops-tom/logs/646b95-0-M002.log
2023-05-24 18:00:05,578 [INFO] wait.py:97 -- ExecutorID 646b95-0 - Waiting for -1% of 1 function activations to complete
2023-05-24 18:00:08,584 [WARNING] future.py:257 -- ExecutorID 646b95-0 | JobID M002 - There was an exception - Activation ID: 4f8232940f6741ff9c80c7c12db8b3cf
2023-05-24 18:00:08,584 [WARNING] future.py:260 -- Exception: ModuleNotFoundError - No module named 'cubed'
2023-05-24 18:00:08,584 [INFO] invokers.py:108 -- ExecutorID 646b95-0 | JobID M003 - Selected Runtime: default-runtime-v39 - 256MB
2023-05-24 18:00:08,588 [INFO] invokers.py:172 -- ExecutorID 646b95-0 | JobID M003 - Starting function invocation: <lambda>() - Total: 1 activations
2023-05-24 18:00:08,589 [INFO] invokers.py:208 -- ExecutorID 646b95-0 | JobID M003 - View execution logs at /tmp/lithops-tom/logs/646b95-0-M003.log
2023-05-24 18:00:08,590 [INFO] wait.py:97 -- ExecutorID 646b95-0 - Waiting for -1% of 1 function activations to complete
2023-05-24 18:00:11,598 [WARNING] future.py:257 -- ExecutorID 646b95-0 | JobID M003 - There was an exception - Activation ID: ab403d5e96084537813e08e0c7ffd07a
2023-05-24 18:00:11,598 [WARNING] future.py:260 -- Exception: ModuleNotFoundError - No module named 'cubed'
---------------------------------------------------------------------------
ModuleNotFoundError                       Traceback (most recent call last)
Cell In[4], line 1
----> 1 measure_reserved_memory(LithopsDagExecutor())

File ~/Documents/Work/Code/cubed/cubed/core/array.py:390, in measure_reserved_memory(executor)
    388 b = xp.negative(a)
    389 peak_memory_callback = PeakMemoryCallback()
--> 390 b.compute(executor=executor, callbacks=[peak_memory_callback])
    391 return peak_memory_callback.peak_memory

File ~/Documents/Work/Code/cubed/cubed/core/array.py:115, in CoreArray.compute(self, executor, callbacks, optimize_graph, **kwargs)
    106 def compute(
    107     self,
    108     *,
   (...)
    112     **kwargs,
    113 ):
    114     """Compute this array, and any arrays that it depends on."""
--> 115     result = compute(
    116         self,
    117         executor=executor,
    118         callbacks=callbacks,
    119         optimize_graph=optimize_graph,
    120         **kwargs,
    121     )
    122     if result:
    123         return result[0]

File ~/Documents/Work/Code/cubed/cubed/core/array.py:316, in compute(executor, callbacks, optimize_graph, *arrays, **kwargs)
    313         executor = PythonDagExecutor()
    315 _return_in_memory_array = kwargs.pop("_return_in_memory_array", True)
--> 316 plan.execute(
    317     executor=executor,
    318     callbacks=callbacks,
    319     optimize_graph=optimize_graph,
    320     array_names=[a.name for a in arrays],
    321     **kwargs,
    322 )
    324 if _return_in_memory_array:
    325     return tuple(a._read_stored() for a in arrays)

File ~/Documents/Work/Code/cubed/cubed/core/plan.py:156, in Plan.execute(self, executor, callbacks, optimize_graph, array_names, **kwargs)
    154 if callbacks is not None:
    155     [callback.on_compute_start(dag) for callback in callbacks]
--> 156 executor.execute_dag(
    157     dag, callbacks=callbacks, array_names=array_names, **kwargs
    158 )
    159 if callbacks is not None:
    160     [callback.on_compute_end(dag) for callback in callbacks]

File ~/Documents/Work/Code/cubed/cubed/runtime/executors/lithops.py:255, in LithopsDagExecutor.execute_dag(self, dag, callbacks, array_names, **kwargs)
    253 def execute_dag(self, dag, callbacks=None, array_names=None, **kwargs):
    254     merged_kwargs = {**self.kwargs, **kwargs}
--> 255     execute_dag(dag, callbacks=callbacks, array_names=array_names, **merged_kwargs)

File ~/Documents/Work/Code/cubed/cubed/runtime/executors/lithops.py:179, in execute_dag(dag, callbacks, array_names, **kwargs)
    177 for stage in pipeline.stages:
    178     if stage.mappable is not None:
--> 179         for _, stats in map_unordered(
    180             executor,
    181             run_func,
    182             list(stage.mappable),
    183             func=stage.function,
    184             config=pipeline.config,
    185             name=name,
    186             use_backups=use_backups,
    187             return_stats=True,
    188         ):
    189             if callbacks is not None:
    190                 event = lithops_stats_to_task_end_event(name, stats)

File ~/Documents/Work/Code/cubed/cubed/runtime/executors/lithops.py:118, in map_unordered(lithops_function_executor, map_function, map_iterdata, include_modules, max_failures, use_backups, return_stats, **kwargs)
    114     if failures > max_failures:
    115         # re-raise exception
    116         # TODO: why does calling status not raise the exception?
    117         future.status(throw_except=True)
--> 118         reraise(*future._exception)
    119     failed.append(future)
    120 else:

File ~/miniconda3/envs/cubed_xarray/lib/python3.9/site-packages/six.py:719, in reraise(tp, value, tb)
    717     if value.__traceback__ is not tb:
    718         raise value.with_traceback(tb)
--> 719     raise value
    720 finally:
    721     value = None

File /workspace/lithops/worker/jobrunner.py:209, in run()

ModuleNotFoundError: No module named 'cubed'
```

I assume this means that lithops needs to be given a runtime environment containing the cubed package, but it's not clear how to pass this in from the existing documentation on `measure_reserved_memory`. Perhaps there should be a section in the docs on how to use `measure_reserved_memory`?

### Additional contract requirements

- `cubed.measure_reserved_memory(executor, work_dir=None, **kwargs)` must accept extra keyword arguments and use them for the computation it runs, in the same way `compute` accepts them. This makes it possible to supply runtime settings for a remote executor in the call, for example a Lithops `config` dictionary, so that the worker can import `cubed`.
- `work_dir` is an optional fsspec URL where intermediate data is stored; it is needed when the executor runs in a cloud environment.
- When the given Lithops executor and runtime settings allow the computation to complete, the function returns a positive number of bytes.
