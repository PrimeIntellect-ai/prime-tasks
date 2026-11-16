Panic on retry
It is probably related to the new `exponential backoff` feature.

The shell-operator pod crashes with panic after some retry attempts. The logs are from an addon-operator, but hook retries cause the same panic.
```
{"binding":"ReloadAllModules","event.type":"OperatorStartup","level":"error","module":"istio","module.state":"failed","msg":"ModuleRun failed. Requeue task to retry after delay. Failed count is 36. Error: helm upgrade failed: exit status 1:\n Error: UPGRADE FAILED: rendered manifests contain a resource that already exists. Unable to continue with update: Secret \"registry\" in namespace \"sample-myrev\" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key \"app.kubernetes.io/managed-by\": must be set to \"Helm\"; annotation validation error: missing key \"meta.helm.sh/release-name\": must be set to \"istio\"; annotation validation error: missing key \"meta.helm.sh/release-namespace\": must be set to \"system\"","operator.component":"taskRunner","queue":"main","task.id":"60561c82-ad02-4543-a8bd-045fb5a81566","time":"2020-12-05T05:59:49Z"}
panic: non-positive interval for NewTicker

goroutine 145 [running]:
time.NewTicker(0x8000000145214600, 0x10c0761fb00)
	/usr/lib/go/src/time/tick.go:23 +0x147
github.com/flant/shell-operator/pkg/task/queue.(*TaskQueue).waitForTask(0xc000becb40, 0x8000000145214600, 0x2654ae2, 0x21)
	/usr/local/go/pkg/mod/github.com/flant/shell-operator@v1.0.0-beta.13/pkg/task/queue/task_queue.go:427 +0x247
github.com/flant/shell-operator/pkg/task/queue.(*TaskQueue).Start.func1(0xc000becb40)
	/usr/local/go/pkg/mod/github.com/flant/shell-operator@v1.0.0-beta.13/pkg/task/queue/task_queue.go:325 +0x166
created by github.com/flant/shell-operator/pkg/task/queue.(*TaskQueue).Start
	/usr/local/go/pkg/mod/github.com/flant/shell-operator@v1.0.0-beta.13/pkg/task/queue/task_queue.go:320 +0x4f
```

### Additional contract requirements

Retry delays must remain positive regardless of how many retry attempts occur, so repeated failures cannot cause shell-operator to panic while scheduling a retry.
