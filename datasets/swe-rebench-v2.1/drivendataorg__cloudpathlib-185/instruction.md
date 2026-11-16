rmtree not working when there is directory inside (google cloud storage)
This package is really helpful to work with different cloud providers but I'm facing an issue when trying to remove directory in gcs.

I tried it even in some test script using this line (after handle the authentication, because I do get True for methods like .exists() or is_dir().

```CloudPath("gs://<bucket>/<path_to_folder(prefix)>").rmtree()```

and getting exception from the  _remove function. ('NoneType' object has no attribute 'delete').

Am I missing something in my usage or maybe it is knows bug?
Thanks
