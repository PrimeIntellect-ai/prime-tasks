[bug] annotations lost from workload when workload is re-added
Given a score workload like:

```
apiVersion: score.dev/v1b1
metadata:
  name: foo
  annotations:
    example.com/thing: foo
containers:
  main:
    image: nginx:latest
```

Generating this once with an existing score file yields:

```
name: temp14
services:
    foo-main:
        annotations:
            compose.score.dev/workload-name: foo
            example.com/thing: foo
        hostname: foo
        image: nginx:latest
```

However, adding another copy of it returns

```
name: temp14
services:
    foo-main:
        annotations:
            compose.score.dev/workload-name: foo
        hostname: foo
        image: nginx:latest
    foo2-main:
        annotations:
            compose.score.dev/workload-name: foo2
            example.com/thing: foo
        hostname: foo2
        image: nginx:latest
```

Note the annotation removed from the source.

The state file contains:

```
workloads:
  foo:
    spec:
      apiVersion: score.dev/v1b1
      containers:
        main:
          image: nginx:latest
      metadata:
        annotations:
          example.com/thing: foo
        name: foo
    file: score.yaml
  foo2:
    spec:
      apiVersion: score.dev/v1b1
      containers:
        main:
          image: nginx:latest
      metadata:
        annotations:
          example.com/thing: foo
        name: foo2
    file: score.yaml2
resources: {}
shared_state: {}
compose_project: temp14
mounts_directory: .score-compose/mounts
```

So the annotation should be there.
