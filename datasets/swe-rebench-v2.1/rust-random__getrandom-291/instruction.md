Expose API interface for MaybeUninit<u8> slice
It is inefficient to zero-fill a large byte buffer before actually being initialized with random bytes. Thus, it would be better if getrandom exposes a function that takes a slice of `MaybeUninit<u8>` so that the user will not have to initialize the buffer.

### Additional contract requirements

Expose the public function `getrandom::getrandom_uninit` accepting `&mut [MaybeUninit<u8>]`. It must fill the entire slice with random bytes without requiring the caller to initialize the storage beforehand. On success, it must return a mutable `&mut [u8]` view of that same storage, with every byte initialized and safe to read.
