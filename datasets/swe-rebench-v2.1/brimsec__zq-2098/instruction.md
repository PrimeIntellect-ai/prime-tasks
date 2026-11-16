Z function for joining array contents into strings
The Z equivalent of the Python:

```
$ python
>>> '.'.join(['www', 'brimsecurity', 'com'])
'www.brimsecurity.com'
```

### Additional contract requirements

Expose this operation as a Z function named `join`. It takes a string array as its first argument and a separator string as its second argument, and returns the elements joined in order with that separator between adjacent elements.
