ReadyCheck.jobReady can SIGSEGV if `job.spec.completions` is not set
`job.spec.completions` is allowed to be null:

>      Specifies the desired number of successfully finished pods the job should
>     be run with. Setting to nil means that the success of any pod signals the
>     success of all pods, and allows parallelism to have any positive value.
>     Setting to 1 means that parallelism is limited to 1 and the success of that
>     pod signals the success of the job. More info:
>     https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/


But `ReadyCheck.jobReady` assumes that the value is _not_ nil:

https://github.com/helm/helm/blob/29da1b94e9e5e7ac800e5a43b0f4dafbe2e89d70/pkg/kube/ready.go#L230

If it _is_ null, then throws an error like:

```
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x1a6d5a5]
```
