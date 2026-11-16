fs.rmdir looks not support "recursive"
```
fs.rmdir("/some/path", {recursive: true })
```

Will get error
```
TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string. Received an instance of Buffer
```
