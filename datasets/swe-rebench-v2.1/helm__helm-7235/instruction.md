Helm3: when App Version is a commit sha, it's getting converted to scientific notation
Output of `helm version`:
`version.BuildInfo{Version:"v3.0.0-rc.3", GitCommit:"2ed206799b451830c68bff30af2a52879b8b937a", GitTreeState:"clean", GoVersion:"go1.13.4"}
`

When app version is a commit sha, it gets converted to a scientific notation. See below for more details on how to reproduce and about the issue:

```
$ helm create test-dummy

$ # change appVersion to 72225e2
$ vi test-dummy/Chart.yaml

$ cat test-dummy/Chart.yaml
apiVersion: v2
name: test-dummy
description: A Helm chart for Kubernetes

# A chart can be either an 'application' or a 'library' chart.
#
# Application charts are a collection of templates that can be packaged into versioned archives
# to be deployed.
#
# Library charts provide useful utilities or functions for the chart developer. They're included as
# a dependency of application charts to inject those utilities and functions into the rendering
# pipeline. Library charts do not define any templates and therefore cannot be deployed.
type: application

# This is the chart version. This version number should be incremented each time you make changes
# to the chart and its templates, including the app version.
version: 0.1.0

# This is the version number of the application being deployed. This version number should be
# incremented each time you make changes to the application.
appVersion: 72225e2

$ helm package test-dummy
Successfully packaged chart and saved it to: /Users/karuppiahoss/oss/helm-issues/issue-6833/dummy-repo-local/test-dummy-0.1.0.tgz

$ # check Chart.yaml contents in tar ball
$ vi test-dummy-0.1.0.tgz
```

`Chart.yaml` contents in packaged tar ball will look like this:
```
apiVersion: v2
appVersion: "7.2225e+06"
description: A Helm chart for Kubernetes
name: test-dummy
type: application
version: 0.1.0
```

And then in repository index:

```
$ helm repo index .
$ # a part of the index
$ cat index.yaml
apiVersion: v1
entries:
  test-dummy:
  - apiVersion: v2
    appVersion: "7.2225e+06"
    created: "2019-11-09T13:07:38.472282+05:30"
    description: A Helm chart for Kubernetes
    digest: 626ec3a02750e500a386d80b053f6f66eef40354a45e8ad18b7ddc8426314037
    name: test-dummy
    type: application
    urls:
    - test-dummy-0.1.0.tgz
    version: 0.1.0
generated: "2019-11-09T13:07:38.471001+05:30"
```

while adding repo and doing search

```
$ # host index.yaml using https://www.npmjs.com/package/serve
$ serve
$ # in another tab
$ helm repo add local http://localhost:5000
$ helm search repo test
helm search repo test
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
local/test-dummy        0.1.0           7.2225e+06      A Helm chart for Kubernetes
```

I expected the search to show `72225e2`, and that happens only when I put double quotes around `72225e2`. Found the issue when checking https://github.com/helm/helm/issues/6849 . I think the lint and package should give error when it detects numbers instead of string in `appVersion` field in the yaml. According to yaml spec, the above is a number.

In helm, instead of erroring out for the number, the number is converted to a string somehow.

### Additional contract requirements

- Linting a chart with a numeric YAML `appVersion` must report that the value is not a string. A value that is already a YAML string must not be reported as a type mismatch. The required safeguard is the lint diagnostic; the packaging output described in the report does not impose a separate packaging failure requirement.
- When linting a chart whose `version` and `appVersion` are numeric YAML values, report these diagnostics in order: `version should be of type string`, `version '7.2445e+06' is not a valid SemVer`, then `appVersion should be of type string`.
