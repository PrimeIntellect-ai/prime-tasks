Metals show error on operators in beginning of the line
### Describe the bug

Error:

![image](https://user-images.githubusercontent.com/20382/213281075-131f01f5-faa0-46d8-b5f2-0efb8a203e3c.png)

Sample code:

```scala
  // This works:
  val httpRoutes = (MetricsApp() ++ HomeApp() ++ GreetingApp()) @@
    Middleware.cors(corsConfig) @@
    Middleware.metrics(MetricsApp.pathLabelMapper) @@
    Middleware.debug

  // This shows error:
  val httpRoutes2 = (MetricsApp() ++ HomeApp() ++ GreetingApp())
    @@ Middleware.cors(corsConfig)
    @@ Middleware.metrics(MetricsApp.pathLabelMapper)
    @@ Middleware.debug
```

Both cases compile and run fine.

### Expected behavior

No error shown in the second sample.

### Operating system

macOS

### Editor/Extension

VS Code

### Version of Metals

0.11.10+56-1cbc85ca-SNAPSHOT

### Extra context or search terms

_No response_

### Additional contract requirements

In Scala 3, a valid infix expression must parse without an error when its operator begins a continuation line. This applies to line-leading infix operators generally, not only `@@`.
