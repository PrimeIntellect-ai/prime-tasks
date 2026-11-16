Does not reject multiple `--image` parameters
## What version of Knative Client?

> Paste output of 'kn version'

```
$ kn version
Version:      v0.10.0
Build Date:   2019-11-07 15:02:21
Git Revision: 22c65d6
Supported APIs:
- serving.knative.dev/v1alpha1 (knative-serving v0.10.0)
```

## What version of Knative Serving running on your cluster?

0.10

## Expected Behavior

When I type `kn update service --image example.com/first --image example.com/second`, I expect to be told that I cannot provide two images.

## Actual Behavior

`kn` accepts the command line without error or warning. It applies the last-provided argument. In the example above this means that the updated service has `example.com/second` as its image.

## Steps to Reproduce the Problem

1. Create a service.
1. Update the service, using two different `--image` parameters.
1. Observe that no error occurs.
1. Use describe to observe that second parameter is applied.
