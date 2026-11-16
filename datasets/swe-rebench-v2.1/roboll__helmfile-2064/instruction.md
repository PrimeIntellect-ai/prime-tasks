feat: Allow more characters in release labels
I have a release label

```
version: x.y.z
```

and helmfile cmd w/ `--selector whatever=dog,version=x.y.z`

```
Malformed label: version=x.y.z. Expected label in form k=v or k!=v in ...[mytemplate.yaml]...
```

Looking at:

https://github.com/roboll/helmfile/blob/c68fc5bc50ea80f5782381f1f4a1ce975ad98e06/pkg/state/release_filters.go#L51

Why are there any character restrictions on helmfile release selectors/labels anyway? They just are used to control what releases helmfile processes, and are not necessarily labels that end up in k8s so I don't see the need to comply with a specific character restriction format?
