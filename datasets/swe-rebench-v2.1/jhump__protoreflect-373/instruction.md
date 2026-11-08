protoparse doesn't increment nested message index for synthetic map entries
Leading to issues like https://github.com/googleapis/api-linter/issues/714.

I think we're missing [HIDDEN] at https://github.com/jhump/protoreflect/blob/8269465cdf82d93fb4ec1cd601d5224f9624418a/desc/protoparse/source_code_info.go[HIDDEN].

### Additional contract requirements

- Generated source-code information must assign nested-type paths that account for synthetic map-entry messages, so paths for subsequent nested messages and their descendants match their positions in the corresponding descriptor.
