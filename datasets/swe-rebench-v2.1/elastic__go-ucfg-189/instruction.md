Empty arrays are turned into nil
When parsing empty arrays from YAML to config objects and unpacking into an untyped representation like `map[string]interface{}` arrays in the original source are turned into `nil`. Marshalling back to YAML this turns into `null` and is thereby not round-trippeable through ucfg:

Consider:
```
node.roles: []
```

```golang
input, err := yaml.Unmarshal(`node.roles: []`)
...
c, err := NewConfig([]byte(input))
...
var output map[string]interface{}
err = c.Unpack(output)
...
yaml.Marshal(output)
```
leaves us with:

```
node.roles: null
```

We have been hit in the ECK operator a couple of times by this issue:
* Kibana Fleet config uses empty arrays to turn off monitoring: https://github.com/elastic/cloud-on-k8s/issues/4853
* Elasticsearch uses empty arrays to express the `coordinating` node role https://github.com/elastic/cloud-on-k8s/issues/3718

We are using untyped `map[string]interface{}` target data structures in the operator for application configuration because it is difficult for us to model each Elastic stack application's configuration completely and for all versions of the Elastic stack that we need to support.

### Additional contract requirements

- When unpacking an empty YAML array into a typed `[]string` field, preserve it as a non-nil empty slice (`[]string{}`).
