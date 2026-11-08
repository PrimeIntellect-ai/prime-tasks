Location#path should have relative path to an include-path root
It seems that `Location#path` is always just `filename.thrift`; this is not very useful.  We'd intended for it to convey the relative position of the file, but from whose perspective?  Not that of the including file, because a file can be included more than once.

It should probably be relative to one of the paths in the include search-path (which includes the compiler's working directory, fyi).  Not sure how exactly to go about this, since we've no tests to verify this behavior and it has likely been broken for a very long time.
