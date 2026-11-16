os.scandir does not work with filedescriptor
**Describe the bug**
I'm using a code that is reading directory content in such a way:
```
os.chdir('/test-volume')
fd = os.open(''/test-volume'', flags=os.O_DIRECTORY)
content = list(os.scandir(fd))
```
This code should return content of `/test-volume` directory. I get:
`[Errno 20] Not a directory in the fake filesystem: '/test-volume/df01d42e-1f05-41fa-9ef3-8463b03ff8f0'`

It would be nice to add support for file descriptors or at least throw NotImplementedError when path is int.

**How To Reproduce**
Shown above.

**Your environment**
```
Linux-5.15.0-48-generic-x86_64-with-glibc2.35
Python 3.10.4 (main, Apr 28 2022, 10:58:00) [GCC 11.2.0]
pyfakefs 4.7.0
```
