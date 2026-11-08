Helm3.beta4 - failed to install chart: value of type interface {} is not assignable to type string
We're trying to install a helm chart, but is not working with helm3 (it works with helm2).
```
❯ helm upgrade --install mychart incubator/raw --version 0.1.0 --namespace default --values myvalues.yaml
Release "mychart" does not exist. Installing it now.
Error: template: raw/templates/resources.yaml:4:12: executing "raw/templates/resources.yaml" at <merge . $template>: error calling merge: reflect.Value.MapIndex: value of type interface {} is not assignable to type string
```

Where (updated) `myvalues.yaml` is:
```
resources:
  - apiVersion: v1
    kind: Secret
    type: kubernetes.io/dockerconfigjson
    metadata:
      name: docker-monitoring-release-flb
    stringData:
      .dockerconfigjson: "{\"auths\":{ \"docker2-monitoring-release-local.test.com\":{\"auth\":\"dXNlcjpwYXNzd29yZAo=\"}}}"
```

Chart is here: https://github.com/helm/charts/tree/master/incubator/raw

Output of `helm version`:
```
version.BuildInfo{Version:"v3.0.0-beta.4", GitCommit:"7ffc879f137bd3a69eea53349b01f05e3d1d2385", GitTreeState:"dirty", GoVersion:"go1.13.1"}
```

Output of `kubectl version`:
```
 kubectl version
Client Version: version.Info{Major:"1", Minor:"14", GitVersion:"v1.14.7", GitCommit:"8fca2ec50a6133511b771a11559e24191b1aa2b4", GitTreeState:"clean", BuildDate:"2019-09-18T14:47:22Z", GoVersion:"go1.12.9", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"14+", GitVersion:"v1.14.6-eks-5047ed", GitCommit:"5047edce664593832e9b889e447ac75ab104f527", GitTreeState:"clean", BuildDate:"2019-08-21T22:32:40Z", GoVersion:"go1.12.9", Compiler:"gc", Platform:"linux/amd64"}
```

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
EKS

### Additional contract requirements

- The `fromYaml` template function parses a YAML document into a `map[string]interface{}`. When the input cannot be parsed into a map, the returned map contains a single `Error` key whose value is a descriptive message that uses the JSON-style wording beginning with `error unmarshaling JSON:`.
