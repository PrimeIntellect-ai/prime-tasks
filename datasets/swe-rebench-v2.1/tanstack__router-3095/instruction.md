Route context not updated if new context is returned in beforeLoad
### Which project does this relate to?

Router

### Describe the bug

while updating from 1.45.4 to 1.91.3 i noticed a new behavior related to router context.
if a new context value is returned from beforeLoad it remains cached and new values for that same context key are not received.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-hsasr5ei?file=src%2Fmain.tsx

### Steps to Reproduce the Bug or Issue

1. click "refresh" button ONCE
2. auth.token and _auth.token have the same value
3. click "refresh" button again
4. auth.token and _auth.token have different values

5. remove the return statement from the indexRoute's beforeLoad
6. refresh the app and do 1. 2. & 3.
7. the behavior is different. auth.token and _auth.token have the same value at all times

### Expected behavior

each call to beforeLoad should receive the latest context even if some of the keys ware overridden by beforeLoad result in the previous call. this used to be the case in 1.45.4

### Screenshots or Videos

https://github.com/user-attachments/assets/b57854e5-2b6f-4b54-92dd-edf2971624cc

### Platform

- OS: mac
- Browser: firefox
- Version: 130


### Additional context

_No response_
