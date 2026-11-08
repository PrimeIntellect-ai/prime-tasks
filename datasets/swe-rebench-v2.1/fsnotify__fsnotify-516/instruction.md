Make watcher `isClosed` public
**Is your feature request related to a problem? Please describe.**
In some cases I am trying to add files to the watcher while the watcher has already been closed. Instead of writing logic on the (OS dependent) error message I receive, I want to check whether the watcher has been closed myself before adding files.

**Describe the solution you'd like**
Make `Watcher.isClosed` public.

**Describe alternatives you've considered**
```
...
err := watcher.Add(path)
if err.Error() == "inotify instance already closed" || err.Error() == "watcher already closed" { // OS dependent
    ...
}
```

**Additional context**
Add any other context or screenshots about the feature request here.

### Additional contract requirements

The requested public way to check whether a watcher has been closed is the
exported `ErrClosed` sentinel. After `Watcher.Close` has been called,
`Watcher.Add` returns `ErrClosed`, and callers detect the closed state by
comparing the returned error against `ErrClosed` (for example with
`errors.Is`).
