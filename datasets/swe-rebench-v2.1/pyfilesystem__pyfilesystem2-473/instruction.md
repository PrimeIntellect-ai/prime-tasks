FTPFS does not list certain folders
It seems that the pub folder is not listed and igrnoed. ftplib does show the folder. This is with python 3.8.

```python
import fs
fs.__version__

# 2.4.12

from fs.ftpfs import FTPFS
a = FTP(host='ftp.ensemblgenomes.org', user="anonymous", passwd="")
a.dir()

""""
drwxr-sr-x   72 ftp      ftp          8192 Feb 16 02:00 pub
-rw-r--r--    1 ftp      ftp            25 Jan 06 22:41 robots.txt
""""

from ftplib import FTP
a = FTPFS(host='ftp.ensemblgenomes.org')
a.listdir('.')

# ['robots.txt']
```

### Additional contract requirements

When the server listing contains the `pub` directory with permissions `drwxr-sr-x`, `FTPFS.listdir('.')` must include `pub` rather than omit it.
