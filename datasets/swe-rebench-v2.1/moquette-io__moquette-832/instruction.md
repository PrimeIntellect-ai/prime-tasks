Shrared buffer issues due to readerIndex
ByteBufs are shared between many sessions and threads. Because if this it is important that none of these session change the `readerIndex` of the shared buffer, and when changing the readerIndex can not be avoided, a `duplicate()` must be made.

In most cases this can be fixed by using the `.getX()` methods instead of the `.readX()` versions.

A PR is on its way.
