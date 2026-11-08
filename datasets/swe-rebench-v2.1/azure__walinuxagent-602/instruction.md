Unhandled error
```
2017/02/06 19:09:15.537324 ERROR get API versions failed with [(000009)HTTP GET failed]
2017/02/06 19:09:15.537516 ERROR Event: name=WALA, op=InitializeHostPlugin, message=
2017/02/06 19:09:15.538399 ERROR host plugin channel is not available
2017/02/06 19:09:15.545516 WARNING Agent WALinuxAgent-2.2.4 failed with exception: 'NoneType' object is not iterable
2017/02/06 19:10:14.026838 WARNING Agent WALinuxAgent-2.2.4 launched with command 'python -u bin/WALinuxAgent-2.2.4-py2.7.egg -run-exthandlers' failed with return code: 1
```

We need to handle this failure more gracefully
