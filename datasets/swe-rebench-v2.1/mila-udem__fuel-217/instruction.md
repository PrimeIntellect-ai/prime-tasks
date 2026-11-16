Problems with using H5PyDataset after deserialization
The traceback is below. It seems that the first request that unpickled dataset gets is `next_epoch`, which calls `reset`, which calls `close`. [HIDDEN]

[HIDDEN]

```
  File "/home/rizar/dist/fully-neural-lvsr/libs/blocks/bin/blocks-continue", line 15, in <module>
    continue_training(args.path)
  File "/home/rizar/dist/fully-neural-lvsr/libs/blocks/blocks/serialization.py", line 220, in continue_training
    main_loop.run()
  File "/home/rizar/dist/fully-neural-lvsr/libs/blocks/blocks/main_loop.py", line 196, in run
    reraise_as(e)
  File "/home/rizar/dist/fully-neural-lvsr/libs/blocks/blocks/utils/__init__.py", line 225, in reraise_as
    six.reraise(type(new_exc), new_exc, orig_exc_traceback)
  File "/home/rizar/dist/fully-neural-lvsr/libs/blocks/blocks/main_loop.py", line 182, in run
    while self._run_epoch():
  File "/home/rizar/dist/fully-neural-lvsr/libs/blocks/blocks/main_loop.py", line 225, in _run_epoch
    get_epoch_iterator(as_dict=True))
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 246, in get_epoch_iterator
    super(Filter, self).get_epoch_iterator(**kwargs)
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/transformers/__init__.py", line 64, in get_epoch_iterator
    self.child_epoch_iterator = self.data_stream.get_epoch_iterator()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/streams.py", line 137, in get_epoch_iterator
    self.next_epoch()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/streams.py", line 128, in next_epoch
    self.data_state = self.dataset.next_epoch(self.data_state)
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/datasets/base.py", line 158, in next_epoch
    return self.reset(state)
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/datasets/base.py", line 139, in reset
    self.close(state)
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/datasets/hdf5.py", line 596, in close
    self._out_of_memory_close()
  File "/home/rizar/dist/fully-neural-lvsr/libs/fuel/fuel/datasets/hdf5.py", line 599, in _out_of_memory_close
    if not self._external_file_handle:
AttributeError: 'H5PYAudioDataset' object has no attribute '_external_file_handle'
```

### Additional contract requirements

After an `H5PYDataset` has been deserialized, starting or resetting an epoch and then requesting dataset data must work without raising `AttributeError` because its external file handle has not yet been initialized.
