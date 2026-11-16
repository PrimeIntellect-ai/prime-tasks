KTB should support not only YAML descriptors, but as well JSON
As a user of the Kafka Topology Builder I don't have special love for YAML and I would love to have it understand as well JSON format for the descriptor files.

### Additional contract requirements

- Topology descriptor files may be written in JSON, with the same structure as the existing YAML descriptors (context, projects, topics and their configuration).
- The descriptor format is selected with the configuration property `topology.file.type`. Its values are `YAML` and `JSON`; when it is not set, descriptors are read as YAML, as before.
- When `topology.file.type` is `JSON`, a JSON descriptor file loaded through the builder's configuration yields the same topology (context, projects, topics) as the equivalent YAML descriptor.
