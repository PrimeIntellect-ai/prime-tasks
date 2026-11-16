Retrieve slice from CxxVector
There is currently no way to get a slice out of a CxxVector. Let's add the a new get_slice() helper so that rust code can use a slice.

Background, we're doing some C++ -> rust API in-house and there's been a wish for that functionality to have "nicer C++ APIs".

Yes, one can use a slice in the FFI API as a work-around. I.e. use rust::Slice<T> in C++.

Pull request incoming.

### Additional contract requirements

- Add a public method `CxxVector<T>::as_slice(&self) -> &[T]` for `T: VectorElement` that returns a slice covering the vector's contiguous storage.
- For an empty vector, `as_slice()` returns an empty slice without invoking undefined behavior.
