test non seekable stream are supported
laspy is written with the idea that reading points sequentially (either by chunk or all at once) should somehow work with non seekable source/stream.

We should have some tests for that
