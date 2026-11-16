Add support to combine service create --filename with other options
<!-- If you need to report a security issue with Knative, send an email to knative-security@googlegroups.com. -->

### Feature request

Per PR #913 review [discussion](https://github.com/knative/client/pull/913#discussion_r451481222) and [comment](https://github.com/knative/client/pull/913#discussion_r450685124). There's a possibility to extend the initial functionality of `kn service create --filename` with other options. In a nutshell to view provided file as a baseline that can be further modified but other option flags.
There should be a reasonable amount of tests added to verify common usage pattern works, e.g. command line options are reflected, take priority and can override existing values, lists are merged etc.

### Use case

Create a service from file and add env variable:
```
kn service create mysvc --filename mysvc.yaml --env VERSION="v2"
```


Create a service from file and specify service account:
```
kn service create mysvc --filename mysvc.yaml --service-account specialSA
```

#### Implementation notes

The following code block should be added and suggestion points from [this PR](https://github.com/knative/client/pull/913#discussion_r451481222) reflected.

[HIDDEN]

<!--
Optional Classifications, remove the '> ' to select:
/kind good-first-issue
> /kind proposal
> /kind doc
> /kind cleanup
-->

### Additional contract requirements

- When `kn service create --filename` is used with other supported create options, treat the service in the file as the baseline and apply those options to it. Command-line values must be reflected in the created service and take precedence over conflicting values in the file.
