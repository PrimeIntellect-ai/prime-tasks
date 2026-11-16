Improve user issue reporting - add copy feature to About popup
When reporting issues, it is useful to know the current version and platform information. This is already provided in the About popup, so it would be convenient to add a feature to copy that information to the clipboard for use in bug (or feature) reports.

The code already wraps copy functionality, so the primary aspect here is to construct the information appropriately from the data available in the About popup.

We expect to standardize on <kbd>c</kbd> for copying, though the command string is somewhat in flux at present. See for example `COPY_STREAM_EMAIL`.

This was previously discussed in `#zulip-terminal>View object has no attribute topic_w` on chat.zulip.org.

### Additional contract requirements

- Pressing <kbd>c</kbd> while the About popup is open copies the popup's information to the clipboard using the controller's `copy_to_clipboard` operation.
- The About popup exposes the copyable text as `copy_info`, a string formatted exactly as:

```text
#### Application
Zulip Terminal: {current Zulip Terminal version}

#### Server
Version: {current server version}

#### Application Configuration
Theme: {theme}
Autohide: {autohide setting}
Maximum footlinks: {maximum footlinks}
Color depth: {color depth}
Notifications: {notifications setting}
Exit confirmation: {exit confirmation setting}

#### Detected Environment
Platform: {platform}
Python: {detected Python version}
```

Each placeholder is replaced by its corresponding value, with no braces in the output.
- The About popup includes the category entry `Copy information to clipboard [c]`.
- Handling a key press in the About popup returns the value returned by the standard popup key handling for that key (typically the key itself when it is not handled).
