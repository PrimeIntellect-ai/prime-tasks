sub-sub-charts of aliased sub-charts not evaluated correctly
# Summary

Given a chart with a subchart `child` and a sub-sub-chart `grandchild`
```
charts/
 + child
   + grandchild
```
where the sub chart is referenced twice with an alias from the `Chart.yaml`:
```
 dependencies:
 - name: child
   alias: foo
   version: 1.0.0
 - name: child
   alias: bar
   version: 1.0.0
```

It is expected that the resources of the `grandchild` chart are rendered twice with different values specified for the two aliases `foo` and `bar`.

# [SSCCE](http://www.sscce.org)
To reproduce it fully, run:

```
mkdir -p parent/charts/child/charts/grandchild/templates
mkdir -p parent/charts/child/templates

echo '
apiVersion: v2
appVersion: 1.0.0
name: grandchild
type: application
version: 1.0.0
' > parent/charts/child/charts/grandchild/Chart.yaml

echo '
apiVersion: v2
appVersion: 1.0.0
name: child
type: application
version: 1.0.0
' > parent/charts/child/Chart.yaml

echo '
apiVersion: v2
appVersion: 1.0.0
name: parent
type: application
version: 1.0.0

dependencies:
- name: child
  alias: foo
  version: 1.0.0
- name: child
  alias: bar
  version: 1.0.0
' > parent/Chart.yaml

echo '
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Chart.Name }}
data:
{{ toYaml .Values | indent 2}}
' > parent/charts/child/templates/dummy.yaml

echo '
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Chart.Name }}-{{ .Values.from }}
data:
{{ toYaml .Values | indent 2}}
' > parent/charts/child/charts/grandchild/templates/dummy.yaml


echo '
foo:
  grandchild:
    from: foo
bar:
  grandchild:
    from: bar
' > parent/values.yaml

helm template parent
```

which prints out:
```
---
# Source: parent/charts/bar/templates/dummy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: bar
data:
  global: {}
  grandchild:
    from: bar
    global: {}
---
# Source: parent/charts/child/charts/grandchild/templates/dummy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grandchild-bar
data:
  from: bar
  global: {}
---
# Source: parent/charts/foo/templates/dummy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: foo
data:
  global: {}
  grandchild:
    from: foo
    global: {}
```

What is missing, is the following:
```
# Source: parent/charts/child/charts/grandchild/templates/dummy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grandchild-foo
data:
  from: foo
  global: {}
```

From my understanding of sub-charts and aliases, this is a bug.

Output of `helm version`:
`version.BuildInfo{Version:"v3.4.1", GitCommit:"c4e74854886b2efe3321e185578e6db9be0a6e29", GitTreeState:"clean", GoVersion:"go1.14.11"}
`
