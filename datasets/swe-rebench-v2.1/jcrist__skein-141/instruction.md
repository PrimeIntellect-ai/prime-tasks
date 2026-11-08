Unable to start a new skein client daemon after having killed the previous one
For some reason, the skein client daemon can be abrupty killed. It turns out we can't start a new skein client daemon after that for the following reason:
When starting a new skein client daemon, a file ~/.skein/daemon is created. This file contains information such that socker address and PID of the skein client daemon. When the skein client daemon is abruptly killed, the process is killed but the file still exists. When trying to start a new skein client daemon, skein first checks whether a daemon is already started by looking for the file ~/.skein/daemon. If it exists, it is assumed a daemon is already started, otherwise it is assumed no daemon is started.
This issue consists in robustifying the way skein checks whether or not a daemon is already started.

### Additional contract requirements

- Starting a new client daemon must be possible when the recorded daemon has been killed and its stale record remains.
- When `driver start` detects a stale driver and starts a replacement, its stderr output must contain the exact text `Previous driver`.
- When `driver start` detects a stale driver and successfully starts a replacement, its stdout output must be non-empty.
- When `driver stop` removes a stale driver file, it must produce no output on stdout or stderr.
