Implement the emoji-free alternative mode
This is for accessibility. The screen reader does not seem to work particularly well with those emojis. This is relatively easy to implement, thanks to the modular logger.

### Additional contract requirements

The application must honor the `EMOJI` environment variable: when it is set to a false boolean value, the application's output must contain no emojis; when it is unset or set to a true boolean value, the application's output must contain emojis. Disabling emojis must not suppress the application's textual log messages.
