Detect PushManager
**Which feature do you want to detect?**
It would be helpful to know if PushManager is available for notifications.

**Which browsers do support this feature?**
Chrome, Firefox should as well, but it has no "PushManager" in window.

**How could it be implemented?**
I'm not sure why Firefox has no "PushManager" even though canIuse shows browser support.

### Additional contract requirements

- Expose the detection under the Modernizr property `pushmanager`.
