'bzl-visibility' checks fail for multiple references to the same workspace
The 'bzl-visibility' check is causing warnings if a rule uses a load statement that changes between '@//', '//' and '@workspace_name//', even if all three are pointing to the same workspace on disk.

For example, the [bazelrules/rules_apple](https://github.com/bazelbuild/rules_apple) will fail with the following error:

```
$ buildifier.mac -lint warn ./apple/apple.bzl
./apple/apple.bzl:18: bzl-visibility: Module "@build_bazel_rules_apple//apple/internal:apple_framework_import.bzl" can only be loaded from files located inside "@build_bazel_rules_apple//apple", not from "//apple". (https://github.com/bazelbuild/buildtools/blob/master/WARNINGS.md#bzl-visibility)
```

### Additional contract requirements

- For loads from `//test/package`, emit these exact findings: `:1: Module "@repo//foo/bar/internal:module.bzl" can only be loaded from files located inside "//foo/bar", not from "//test/package".`; `:2: Module "@repo//foo/bar/private:module.bzl" can only be loaded from files located inside "//foo/bar", not from "//test/package".`; and `:4: Module "@repo/internal:module.bzl" can only be loaded from files located inside "@repo", not from "//test/package".`
