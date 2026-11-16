Exceptions no longer stringify
In past versions of fontoxpath, exceptions would stringify to the error message. This seems no longer to be the case; they just give the dreaded `[object Object]`.

I can recover the error message by printing `error.h` (in version 3.30.2), but that's fragile and depends on the minification of the exception object.
