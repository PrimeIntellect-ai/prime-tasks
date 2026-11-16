Using a hashed password for authentication, if the password contains a colon (:) , login will fail.
**Problem**

Using a hashed password for authentication, if the password contains a colon (:) , login will fail.

**Configuration**

The command I ran is as follows:
./dufs -a "admin:$(mkpasswd -m sha-512 "a:b")@/:ro"

I accessed http://127.0.0.1:5000/, entered the username 'admin' and the password 'a:b', but the login attempt was unsuccessful.

**Environment Information**
 - Dufs version: 0.42.0
 - Browser/Webdav info: Chrome
 - OS info: ubuntu 22.04
