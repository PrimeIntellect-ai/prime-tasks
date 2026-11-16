Handle batched mouse events
[This snippet](https://github.com/charmbracelet/bubbletea/blob/a6f46172ec4436991b90c2270253b2d212de7ef3/mouse.go#L67) stops all events that are not 6 bytes long from being processed as mouse events.

However, some terminals may emit multiple mouse events per "tick."
- alacritty emits two events when a mouse down and mouse move occur simultaneously, dropping the event
- termux emits the mouse down and mouse up event simultaneously for mouse clicks (this stops all mouse clicks from registering)
  *example of mouse click:*
  ```
  (dlv) p string(buf)
  "\x1b[M +6\x1b[M#+6"
  ```

### Reproducing
- build the "mouse" example with optimizations off `-gcflags "all=-N -l"`
- break on [line 68 of mouse.go](https://github.com/charmbracelet/bubbletea/blob/a6f46172ec4436991b90c2270253b2d212de7ef3/mouse.go#L68)
- trigger breakpoint by moving mouse and pressing mouse button simultaneously

### Expected Behaviour
Should register "batched" mouse events, like ncurses-based apps.

### Additional contract requirements

- Add a function `readInputs(input io.Reader) ([]Msg, error)` in package `tea` that reads key and mouse input and returns all parsed messages. When the input contains multiple batched mouse events, every event must be returned as a separate `MouseMsg`, not only the first one.
- Add a function `parseX10MouseEvents(buf []byte) ([]MouseEvent, error)` in package `tea` that parses one or more X10 mouse event sequences from the buffer and returns all detected events, or an error if the buffer does not contain valid X10 mouse event data.
