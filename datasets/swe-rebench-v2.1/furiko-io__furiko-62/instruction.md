JobMutationWebhook nil pointer crash
Encountered panic in nil pointer exception:

```
2022/04/17 15:42:29 http: panic serving 10.244.0.1:8270: runtime error: invalid memory address or nil pointer dereference
goroutine 29143 [running]:
net/http.(*conn).serve.func1()
        /opt/hostedtoolcache/go/1.17.8/x64/src/net/http/server.go:1802 +0xb9
panic({0x17b32c0, 0x299acd0})
        /opt/hostedtoolcache/go/1.17.8/x64/src/runtime/panic.go:1047 +0x266
github.com/furiko-io/furiko/pkg/execution/mutation.(*Mutator).MutateJob(0xc000837630, 0xc00000a780)
        /home/runner/work/furiko/furiko/pkg/execution/mutation/mutation.go:131 +0xd8
github.com/furiko-io/furiko/pkg/execution/webhooks/jobmutatingwebhook.(*Webhook).Patch(0xc00000a5a0, 0xc000479040, 0x7fe542fa45b8)
        /home/runner/work/furiko/furiko/pkg/execution/webhooks/jobmutatingwebhook/webhook.go:176 +0x57
github.com/furiko-io/furiko/pkg/execution/webhooks/jobmutatingwebhook.(*Webhook).Handle(0x1c40778, {0xc00045bf40, 0x1c1e0b8}, 0xc000479040)
        /home/runner/work/furiko/furiko/pkg/execution/webhooks/jobmutatingwebhook/webhook.go:140 +0x26c
github.com/furiko-io/furiko/pkg/runtime/httphandler.HandleAdmissionWebhook.func1({0x1c1e0b8, 0xc00011c8c0}, 0xc00052ef00)
        /home/runner/work/furiko/furiko/pkg/runtime/httphandler/webhooks.go:67 +0x123
net/http.HandlerFunc.ServeHTTP(0xc00013ad00, {0x1c1e0b8, 0xc00011c8c0}, 0xc00011c8c0)
        /opt/hostedtoolcache/go/1.17.8/x64/src/net/http/server.go:2047 +0x2f
net/http.(*ServeMux).ServeHTTP(0xc0001a5928, {0x1c1e0b8, 0xc00011c8c0}, 0xc00052ef00)
        /opt/hostedtoolcache/go/1.17.8/x64/src/net/http/server.go:2425 +0x149
net/http.serverHandler.ServeHTTP({0x1c109d0}, {0x1c1e0b8, 0xc00011c8c0}, 0xc00052ef00)
        /opt/hostedtoolcache/go/1.17.8/x64/src/net/http/server.go:2879 +0x43b
net/http.(*conn).serve(0xc00037c960, {0x1c22878, 0xc000600720})
        /opt/hostedtoolcache/go/1.17.8/x64/src/net/http/server.go:1930 +0xb08
created by net/http.(*Server).Serve
        /opt/hostedtoolcache/go/1.17.8/x64/src/net/http/server.go:3034 +0x4e8
```

### Additional contract requirements

- Add a public constructor `NewJobPatcher(ctrlContext controllercontext.Context) *JobPatcher` in package `github.com/furiko-io/furiko/pkg/execution/mutation`.
- Add a public method `(*JobPatcher) Patch(operation admissionv1.Operation, oldRj, rj *execution.Job) *webhook.Result` that dispatches on the admission operation. For `Create` it applies the creation-time mutation (adding the default finalizer and evaluating the referenced JobConfig); for `Update` it applies the update-time mutation (setting defaults such as the job type, TTL, and template defaults) without adding the creation-only finalizer.
- JobConfig mutation must not set a pod template restart policy merely because it is unspecified.
- Add a public constructor `NewJobConfigPatcher(ctrlContext controllercontext.Context) *JobConfigPatcher` in package `github.com/furiko-io/furiko/pkg/execution/mutation`.
- Add a public method `(*JobConfigPatcher) Patch(operation admissionv1.Operation, oldRjc, rjc *execution.JobConfig) *webhook.Result` that dispatches on the admission operation. For `Create` it applies the creation-time mutation (bumping the schedule's `LastUpdated` when a schedule is present); for `Update` it applies the update-time mutation (bumping the schedule's `LastUpdated` when the schedule changed).
