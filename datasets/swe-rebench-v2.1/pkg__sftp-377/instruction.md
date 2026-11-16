Request server: allow to open a file for both reading and writing
Hi,

based on the SFTP specs opening a file for both reading and writing is allowed

```
SSH_FXF_READ
      Open the file for reading.

SSH_FXF_WRITE
      Open the file for writing.  If both this and SSH_FXF_READ are
      specified, the file is opened for both reading and writing.
```

pkg/sftp currently does not support this mode. I think this is the reason for this [issue](https://github.com/drakkan/sftpgo/issues/155#issuecomment-676798820).

Here are the OpenSSH logs when opening a file using sshfs-win:

```
ago 20 16:29:10 p1 sftp-server[9254]: debug3: request 168: open flags 3
ago 20 16:29:10 p1 sftp-server[9254]: open "/tmp/a/Nuovo documento di testo (2).txt" flags READ,WRITE mode 00
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 168: sent handle handle 2
ago 20 16:29:10 p1 sftp-server[9254]: debug3: request 169: lstat
ago 20 16:29:10 p1 sftp-server[9254]: lstat name "/tmp/a/Nuovo documento di testo (2).txt"
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 169: sent attrib have 0xf
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 170: write "/tmp/a/Nuovo documento di testo (2).txt" (handle 2) off 0 len 15
ago 20 16:29:10 p1 sftp-server[9254]: debug3: request 170: sent status 0
ago 20 16:29:10 p1 sftp-server[9254]: sent status Success
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 171: fstat "/tmp/a/Nuovo documento di testo (2).txt" (handle 2)
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 171: sent attrib have 0xf
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 172: fsetstat handle 2
ago 20 16:29:10 p1 sftp-server[9254]: set "/tmp/a/Nuovo documento di testo (2).txt" size 15
ago 20 16:29:10 p1 sftp-server[9254]: debug3: request 172: sent status 0
ago 20 16:29:10 p1 sftp-server[9254]: sent status Success
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 173: fstat "/tmp/a/Nuovo documento di testo (2).txt" (handle 2)
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 173: sent attrib have 0xf
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 174: read "/tmp/a/Nuovo documento di testo (2).txt" (handle 2) off 0 len 4096
ago 20 16:29:10 p1 sftp-server[9254]: debug1: request 174: sent data len 15
ago 20 16:29:10 p1 sftp-server[9254]: debug3: request 175: close handle 2
ago 20 16:29:10 p1 sftp-server[9254]: close "/tmp/a/Nuovo documento di testo (2).txt" bytes read 15 written 15
```

as you can see OpenSSH uses the same handle for both reads and writes.

How do you suggest to support this mode in pkg/sftp? Is ok a new request method, for example "PutGet" mapped to a new interface, for example Filereadwrite that returns both an io.ReaderAt and an io.WriterAt? Do you have other suggestions? Thank you
