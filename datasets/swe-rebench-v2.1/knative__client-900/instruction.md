`kn trigger describe foo` panics when Sink uses URI instead of Ref
### Bug report

This is basically a replay of #847.

[HIDDEN] It appears to be identical to the `source describe` code as it was before #848 was merged.

### Expected behavior

I expect that `kn trigger describe` does not have an error when inspecting a Trigger that uses a URI instead of a Ref.

### Steps to reproduce the problem

```
$ kn trigger create example-trigger --filter type=dev.knative.example.com --sink http://example.com/
Trigger 'example-trigger' successfully created in namespace 'default'.

$ kn trigger describe example-trigger
Name:         example-trigger
Namespace:    default
Labels:       eventing.knative.dev/broker=default
Annotations:  eventing.knative.dev/creator=jchester@pivotal.io, eventing.knative.dev/lastModifier ...
Age:          25s
Broker:       default
Filter:
  type:       dev.knative.example.com

panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0x1f9cd59]

goroutine 1 [running]:
knative.dev/client/pkg/kn/commands/trigger.writeSink(0x24ea4a0, 0xc00060a930, 0xc00047ebb0)
	/home/prow/go/src/knative.dev/client/pkg/kn/commands/trigger/describe.go:100 +0x89
knative.dev/client/pkg/kn/commands/trigger.NewTriggerDescribeCommand.func1(0xc0001dcdc0, 0xc00022a7e0, 0x1, 0x1, 0x0, 0x0)
	/home/prow/go/src/knative.dev/client/pkg/kn/commands/trigger/describe.go:76 +0x230
github.com/spf13/cobra.(*Command).execute(0xc0001dcdc0, 0xc00022a7b0, 0x1, 0x1, 0xc0001dcdc0, 0xc00022a7b0)
	/home/prow/go/src/knative.dev/client/vendor/github.com/spf13/cobra/command.go:832 +0x460
github.com/spf13/cobra.(*Command).ExecuteC(0xc0000dc580, 0x0, 0x0, 0xc00000e048)
	/home/prow/go/src/knative.dev/client/vendor/github.com/spf13/cobra/command.go:920 +0x2fb
github.com/spf13/cobra.(*Command).Execute(...)
	/home/prow/go/src/knative.dev/client/vendor/github.com/spf13/cobra/command.go:870
main.main()
	/home/prow/go/src/knative.dev/client/cmd/kn/main.go:42 +0x158
```

### kn version

<!-- Please paste the output of 'kn version' in the code block below -->

```
Version:      v0.15.1
Build Date:   2020-06-03 16:11:35
Git Revision: 0cac223
Supported APIs:
* Serving
  - serving.knative.dev/v1 (knative-serving v0.15.0)
* Eventing
  - sources.knative.dev/v1alpha2 (knative-eventing v0.15.0)
  - eventing.knative.dev/v1alpha1 (knative-eventing v0.15.0)
```

### Knative (serving/eventing) version

v0.15

### Additional contract requirements

- For a Trigger with a URI sink, the `kn trigger describe` output must include `Sink:`, `URI`, `https`, and `foo`.
