Debug mode documentation incorrect
https://github.com/gin-gonic/gin/blob/094f9a9105f8e7b971a01a64677eef5a1f7bcd9b/mode.go#L31-L32 contradicts https://github.com/gin-gonic/gin/blob/094f9a9105f8e7b971a01a64677eef5a1f7bcd9b/debug.go#L52-L59

The same for https://github.com/gin-gonic/gin/blob/094f9a9105f8e7b971a01a64677eef5a1f7bcd9b/debug.go#L99-L103 contradicts https://github.com/gin-gonic/gin/blob/094f9a9105f8e7b971a01a64677eef5a1f7bcd9b/mode.go#L40-L41

### Additional contract requirements

- Debug output produced while Gin is in debug mode (for example route registration messages, warnings, and loaded-template messages) must be written to the public `DefaultWriter` variable.
- Debug error output must be written to the public `DefaultErrorWriter` variable.
