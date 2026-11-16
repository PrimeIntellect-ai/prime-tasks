Discourage accidental use of mbed-official keyword
There have been several cases where target descriptions have been published with descriptions and keywords indicating that they are officially supported, when in fact they aren't.

yotta should warn when these keywords are used, to make sure that their use is intentional.

### Additional contract requirements

- When publishing a module whose keywords include `mbed-official`, yotta must emit `Is this really an officially supported mbed module` in stdout or stderr and return a nonzero exit status.
