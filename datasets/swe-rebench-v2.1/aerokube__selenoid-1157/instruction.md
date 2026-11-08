Support non-standard Selenoid features as WebDriver protocol extensions
Should be able to use the following urls (WebDriver protocol extensions):
```
http://selenoid-host.example.com:4444/wd/hub/session/<id>/selenoid/vnc -> returns WebSocket
http://selenoid-host.example.com:4444/wd/hub/session/<id>/selenoid/logs -> returns WebSocket
http://selenoid-host.example.com:4444/wd/hub/session/<id>/selenoid/file/filename.ext -> returns file
```

### Additional contract requirements

The protocol extension URLs are served under the vendor prefix `aerokube`, i.e. the URLs above are `/wd/hub/session/<id>/aerokube/vnc`, `/wd/hub/session/<id>/aerokube/logs` and `/wd/hub/session/<id>/aerokube/download/<filename>`. The following extension URLs must be supported:

- `/wd/hub/session/<id>/aerokube/vnc` -> returns WebSocket
- `/wd/hub/session/<id>/aerokube/logs` -> returns WebSocket
- `/wd/hub/session/<id>/aerokube/download/<filename>` -> returns file
- `/wd/hub/session/<id>/aerokube/clipboard` -> GET returns the clipboard contents, POST sets the clipboard contents
