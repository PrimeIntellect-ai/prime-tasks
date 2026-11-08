logging.Server prints a wrong caller path
<!--
Please answer these questions before submitting your issue. Thanks!
For questions please use one of our forums: https://go-kratos.dev/docs/getting-started/faq
-->
#### What happened:

Consider this code:
```go
logger := log.With(log.NewStdLogger(os.Stdout),
	"caller", log.DefaultCaller,
)

helper := log.NewHelper(logger)
helper.Info("foo")

srv := http.NewServer(
	http.Address(":9090"),
	http.Middleware(logging.Server(logger)),
)
```

helper.Info's caller field report where the helper.Info called (e.g. main.go:10). But logger in logger.Server is not.

#### What you expected to happen:

logger.Server's caller path "level" should same as "helper.Log"

#### How to reproduce it (as minimally and precisely as possible):

Please refer this [repo](https://github.com/kvii/report_kratos_logging_issue).

#### Anything else we need to know?:

这绝对不是调一下 caller 层数或添加自定义 calller 逻辑（比如 for 循环匹配第一个不是 kratos 的目录）能解决的问题。

#### Environment:
- Kratos version (use `kratos -v`): v2.7.2
- Go version (use `go version`): 1.21.5
- OS (e.g: `cat /etc/os-release`): -
- Others: -
