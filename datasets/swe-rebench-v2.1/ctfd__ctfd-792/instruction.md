Not possible to download files as anonymous user
**Environment**:

  - CTFd Version/Commit: 2.0.0 from master
  - Operating System: Debian Stretch, Ubuntu 18.04, ...
  - Web Browser and Version: Firefox 63

**What happened?**

* In admin, set visibility of challenges to public
* Logout
* Open challenge view (`/challenges`)
* Click on a challenge with a file
* Try to download the file (`/files/c378d661d2c9e103c4409cd4c92d801f/alice_bob.py`
* => Error 403

**What did you expect to happen?**

* ...
* Click on a challenge with a file
* Try to download the file
* File downloads

**How to reproduce your issue**

_see above_

**Any associated stack traces or error logs**

_none_
