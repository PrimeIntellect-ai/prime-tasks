Make compression_wrapper accept filename again
The `smart_open.compression.compression_wrapper()` used to accept a `filename` parameter. This is necessary in cases where the input `file_obj` cannot be modified = monkey-patchong a `.name` attribute into it is undesirable.

This feature was removed in 930c897aab96821bd5fff9cb6b0a2f8ab922f51e – @mpenkov do you remember why?

I propose bringing it back, because the alternative is hacky: accessing the protected `compression._COMPRESSOR_REGISTRY` dict directly.

Relatedly, the extension-matching logic is case-sensitive, `.gz` != `.GZ` etc. I don't see much point to this – should be case-insensitive IMO.
