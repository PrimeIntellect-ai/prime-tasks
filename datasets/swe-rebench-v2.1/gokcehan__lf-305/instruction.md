Log files remain in /tmp if closed by window manager.
If I close that instance of lf by pressing the shortcut bind within lf, it closes with no abnormal effects...

but if I close that with my window manager's typical shortcut for closing programs `super + q` as it happens, lf's log file remains in `/tmp` forever (well until `/tmp` cleanup).

You say in #65 that leftovers will remain in `/tmp` for instances closed by errors, but here it seems that any external closing does the same.

Not sure if this is a decided choice or what, but seems abnormal among programs.

I'm using dwm, if that's relevant.

### Additional contract requirements

- When the lf client receives a hangup (SIGHUP) or termination (SIGTERM) signal sent to its process, for example when the window manager closes its window, it must stop and remove its client log file from the temporary directory, the same way it cleans up when quit from within lf.
