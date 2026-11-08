Bug: unittest test_standard_iterator_unbuffered seems buggy
Subtle bug, but here it goes:

On test_standard_iterator_unbuffered (tests/unit/form_tests/utils_test/test_core_DataChunkIterator), line 57 and 59, we have
dci = DataChunkIterator(data=range(10), buffer_size=1)
self.assertTupleEqual(dci.max_shape, (None,))

I claim it should read:
self.assertTupleEqual(dci.max_shape, (10,))

This is because in the constructor of DataChunkIterator we have:

```        if self.max_shape is None:
            # If the self.data object identifies it shape then use it
            if hasattr(self.data,  "shape"):
                self.max_shape = self.data.shape
                # Avoid the special case of scalar values by making them into a 1D numpy array
                if len(self.max_shape) == 0:
                    self.data = np.asarray([self.data, ])
                    self.max_shape = self.data.shape
                    self.__data_iter = iter(self.data)
            # Try to get an accurate idea of max_shape for other Python datastructures if possible.
            # Don't just callget_shape for a generator as that would potentially trigger loading of all the data
            [HIDDEN]```
```

Initially, max_shape is None will be true, and data will not have attribut.  [HIDDEN]

However, this will not evaluate to true in python3, because data is type "range" (in python 2, it is type list, so the line will evaluate True, and max_shape would be set to 10).

In python3 max_shape will not be set, so the test will pass, but I think this is incorrect behavior for the test.  [HIDDEN]  This is a short job, but one prone to mistakes, and since it involves rewriting test behavior, I vote for @ajtritt to make the modifications if he agrees.

### Additional contract requirements

- For `DataChunkIterator(data=range(10), buffer_size=1)` and `DataChunkIterator(data=range(10), buffer_size=3)`, `max_shape` must be `(10,)` for both, regardless of buffer size.
- For `DataChunkIterator(data=range(10), buffer_size=1)` and `DataChunkIterator(data=range(10), buffer_size=3)`, `recommended_data_shape()` must return `(10,)` both before and after iteration.
