Is IndexableDataset.__getattr__ interfering with pickling?
Here's a small example exhibiting the issue:

``` python
>>> import pickle
>>> from fuel.datasets import IndexableDataset
>>> dataset = IndexableDataset({'features': [[0, 0], [1, 1]]})
>>> dataset = pickle.loads(pickle.dumps(dataset))
TypeError: argument of type 'NoneType' is not iterable
```

[HIDDEN]

### Additional contract requirements

After a successful pickle round-trip, the restored dataset remains usable and retains the data that was stored in it.
