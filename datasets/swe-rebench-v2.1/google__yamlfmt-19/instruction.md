Support multiple documents in single file
The default `Unmarshal` behaviour in `yaml.v3` will only read and output the first document in a multi-document yaml file. I was unaware that this was possible, let alone common in Kubernetes so I did not test it initially.

[HIDDEN] This behaviour might diverge heavily from the basic formatter, so it might need to be an entirely new one, but I will see if I can make it work by default.

### Additional contract requirements

When formatting a YAML stream containing multiple documents, preserve every document in the output in the same order as the input.
