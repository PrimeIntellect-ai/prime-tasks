Policy bot stuck on `Commit hash does not have a pushed date`
Hello, we are seeing errors on policy bot where it's stuck on trying to get the `pushed date`
![image](https://github.com/palantir/policy-bot/assets/74798317/86d17c26-3d38-4c12-a00c-3fa196d5526a)

Is there anything we can do to debug this issue?

Attached is the stack trace

```go
failed to compute approval status: failed to list commits: Commit f3bed522f4 does not have a pushed date. This is usually caused by delays in the GitHub API
github.com/palantir/policy-bot/policy/approval.(*Rule).filteredCommits
	/home/runner/work/policy-bot/policy-bot/policy/approval/approve.go:345
github.com/palantir/policy-bot/policy/approval.(*Rule).IsApproved
	/home/runner/work/policy-bot/policy-bot/policy/approval/approve.go:204
github.com/palantir/policy-bot/policy/approval.(*Rule).Evaluate
	/home/runner/work/policy-bot/policy-bot/policy/approval/approve.go:141
github.com/palantir/policy-bot/policy/approval.(*RuleRequirement).Evaluate
	/home/runner/work/policy-bot/policy-bot/policy/approval/evaluate.go:63
github.com/palantir/policy-bot/policy/approval.(*OrRequirement).Evaluate
	/home/runner/work/policy-bot/policy-bot/policy/approval/evaluate.go:86
github.com/palantir/policy-bot/policy/approval.(*AndRequirement).Evaluate
	/home/runner/work/policy-bot/policy-bot/policy/approval/evaluate.go:146
github.com/palantir/policy-bot/policy/approval.(*evaluator).Evaluate
	/home/runner/work/policy-bot/policy-bot/policy/approval/evaluate.go:39
github.com/palantir/policy-bot/policy.evaluator.Evaluate
	/home/runner/work/policy-bot/policy-bot/policy/policy.go:80
github.com/palantir/policy-bot/server/handler.(*EvalContext).EvaluatePolicy
	/home/runner/work/policy-bot/policy-bot/server/handler/eval_context.go:125
github.com/palantir/policy-bot/server/handler.(*Details).ServeHTTP
	/home/runner/work/policy-bot/policy-bot/server/handler/details.go:132
github.com/bluekeyes/hatpear.Try.func1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/bluekeyes/hatpear/hatpear.go:84
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
goji%2eio.dispatch.ServeHTTP
	/home/runner/work/policy-bot/policy-bot/vendor/goji.io/dispatch.go:17
github.com/palantir/policy-bot/server/handler.RequireLogin.func1.1
	/home/runner/work/policy-bot/policy-bot/server/handler/login.go:95
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
goji%2eio.(*Mux).ServeHTTP
	/home/runner/work/policy-bot/policy-bot/vendor/goji.io/mux.go:74
goji%2eio.dispatch.ServeHTTP
	/home/runner/work/policy-bot/policy-bot/vendor/goji.io/dispatch.go:17
goji%2eio.(*Mux).ServeHTTP
	/home/runner/work/policy-bot/policy-bot/vendor/goji.io/mux.go:74
goji%2eio.dispatch.ServeHTTP
	/home/runner/work/policy-bot/policy-bot/vendor/goji.io/dispatch.go:17
github.com/bluekeyes/hatpear.Recover.func1.1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/bluekeyes/hatpear/hatpear.go:113
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
github.com/bluekeyes/hatpear.Catch.func1.1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/bluekeyes/hatpear/hatpear.go:60
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
github.com/palantir/go-baseapp/baseapp.AccessHandler.func1.1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/palantir/go-baseapp/baseapp/middleware.go:88
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
github.com/rs/zerolog/hlog.RequestIDHandler.func1.1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/rs/zerolog/hlog/hlog.go:187
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
github.com/palantir/go-baseapp/baseapp.NewMetricsHandler.func1.1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/palantir/go-baseapp/baseapp/middleware.go:55
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
github.com/rs/zerolog/hlog.NewHandler.func1.1
	/home/runner/work/policy-bot/policy-bot/vendor/github.com/rs/zerolog/hlog/hlog.go:29
net/http.HandlerFunc.ServeHTTP
	/opt/hostedtoolcache/go/1.20.4/x64/src/net/http/server.go:2122
goji%2eio.(*Mux).ServeHTTP
	/home/runner/work/policy-bot/policy-bot/vendor/goji.io/mux.go:74
```

### Additional contract requirements

- The `pull` package (import path `github.com/palantir/policy-bot/pull`) exposes `NewGitHubContext(ctx context.Context, mbrCtx MembershipContext, client *github.Client, v4client *githubv4.Client, loc Locator, doNotLoadCommitPushedDate bool) (Context, error)`, which creates a context for the specified pull request.
- When `doNotLoadCommitPushedDate` is true, the context does not load commit pushed dates: a commit whose pushed date is absent from the pull request commit data is returned with no pushed date.
