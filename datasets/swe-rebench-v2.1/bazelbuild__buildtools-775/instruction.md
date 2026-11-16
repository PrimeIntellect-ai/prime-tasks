Buildifier: warning function-docstring-args cannot handle keyword-only function arguments
While working on https://github.com/bazelbuild/rules_proto/pull/22, I noticed that buildifier doesn't know how to handle the separator for keyword-only function arguments.

See https://buildkite.com/bazel/rules-proto/builds/258#76717e64-ae09-4bf7-ac1a-0861e530e45b

```starlark
def direct_source_infos(proto_info, *, provided_sources = []):
    """Returns sequence of `ProtoFileInfo` for `proto_info`'s direct sources.

    Files that are both in `proto_info`'s direct sources and in
    `provided_sources` are skipped. This is useful, e.g., for well-known
    protos that are already provided by the Protobuf runtime.

    Args:
      proto_info: An instance of `ProtoInfo`.
      provided_sources: Optional. A sequence of import paths to ignore.

    Returns: A sequence of `ProtoFileInfo` containing information about
        `proto_info`'s direct sources.
    """

    files = [_info(f, proto_info) for f in proto_info.direct_sources]
    return [f for f in files if f.import_path not in provided_sources]
```

```shell
$ buildifier --lint=warn --warnings=all proto/private/utils/direct_source_infos.bzl
proto/private/utils/direct_source_infos.bzl:26: function-docstring-args: Argument "" is not documented. (https://github.com/bazelbuild/buildtools/blob/master/WARNINGS.md#function-docstring-args)
```

Adding documentation for `*:` doesn't seem to fix it (and TBH, documenting that would be weird).

### Additional contract requirements

- In an `Args` section, report `*:` as `Argument "*" is documented but doesn't exist in the function signature.` and a bare `:` as `Argument "" is documented but doesn't exist in the function signature.`
