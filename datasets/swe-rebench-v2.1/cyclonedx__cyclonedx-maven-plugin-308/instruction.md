Cyclic Dependency when project depends on itself
Maven normally excludes cyclic dependencies, however there is one case when this is allowed.  This results in recursion leading to a StackOverflowError.

This was first discovered when generating a bom for the `netty-tcnative` project which includes `netty-tcnative-boringssl-static`.
 The `netty-tcnative-boringssl-static` project has dependencies on itself, albeit with individual qualifiers (such as `linux-x86_64`) for each of its supported binaries.

### Additional contract requirements

- For this case, the generated BOM must include components and dependency entries for `pkg:maven/com.example.cyclic/cyclic_A@1.0.0?classifier=classifier_1&type=jar`, `pkg:maven/com.example.cyclic/cyclic_A@1.0.0?classifier=classifier_2&type=jar`, and `pkg:maven/com.example.cyclic/cyclic_A@1.0.0?classifier=classifier_3&type=jar`. The dependency entry `pkg:maven/com.example.cyclic/cyclic_A@1.0.0?type=jar` must reference exactly these three classifier PURLs, and each classifier dependency entry must have no dependency references.
