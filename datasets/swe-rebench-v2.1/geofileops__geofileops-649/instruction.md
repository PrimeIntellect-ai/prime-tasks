BUG: in copy_layer and append_to the default dst_layer is not the stem of the filename
The documentation states it should work like this, and this is about the only function in `geofileops` where this is the case, which doesn't give a very consistent feeling.

It is a non-backwards compatible change, but in most cases this will probably don't give any issues.
