Promote single-file timeout to env variable
https://github.com/sissbruecker/linkding/blob/5d8fdebb7c4918c3face9478543ccf86b2db47ef/bookmarks/services/singlefile.py#L27

Can you please promote single-file timeout value to an environment variable? I run linkding on a raspberry pi and sometimes taking a snapshot is sloooow.

For example:
```
time single-file https://www.hightidestoredtla.shop/products/bullet-ballpoint-pen-light?variant=38
087018184895

real    1m31.228s
user    0m13.667s
sys     0m11.835s
```

In my case I'd like to set a maybe 2 or 3 minute timeout.

### Additional contract requirements

- The snapshot timeout is configurable through the environment variable `LD_SINGLEFILE_TIMEOUT_SEC`, given in seconds. When the variable is not set, the timeout defaults to 60 seconds.
- The timeout is exposed as the Django setting `LD_SINGLEFILE_TIMEOUT_SEC` (a number of seconds, default 60), which controls how long the snapshot process may run.
- `bookmarks.services.singlefile.SingeFileError` is raised when the snapshot process times out.
