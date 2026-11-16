unexpected changes in `camelToSnake()` at v1.176.1
## Probrem

I noticed that the behavior of the `camelToSnake()` changed with the fix in https://github.com/stephenh/ts-proto/pull/1046.

Specifically, the behavior has changed when the string to be converted contains numbers.
For example, if the package name includes a version like `v1`, it is affected.

With the following code:

```proto
package sample.v1;
```

- Prior to version 1.176.0, the generated code was:

```ts
export const SAMPLE_V1_PACKAGE_NAME = "sample.v1";
```

- In version 1.176.1, the generated code is now:

```ts
export const SAMPLE_V_1_PACKAGE_NAME = "sample.v1";
```

As a result, the generated constant name has changed, causing build errors.

To clarify, these codes are generated when using the `nestJs=true` option.

Upon reviewing the PR, it seems this behavior change was not intended.
This unexpected change in a patch version has caused a lot of confusion.

---

That said, the changes in https://github.com/stephenh/ts-proto/pull/1046 appear reasonable.
Reverting the commit does not seem to be a good solution.

I reviewed the documentation and code of the `case-anything` package, which is used internally by `camelToSnake()`, and it seems difficult to control the handling of numbers externally.

Moreover, there is no set specification on how to handle numbers in snake_case, and there are multiple opinions on the matter. Therefore, I don't think the behavior in v1.176.1 is incorrect.

How do you plan to address this issue?

If the behavior in v1.176.1 is considered correct, I believe it should be clearly documented, and a minor version update should be made.

Sorry I can't offer any concrete suggestions for improvement.

I am always grateful for this package. Thank you very much.

---


<details>
<summary>Environment Used for Testing</summary>

<br>

The information about the environment I used for testing is as follows:

```
├── proto
│   └── sample
│       └── v1
│           └── sample.proto
├── buf.gen.yaml
```

buf.gen.yaml
```yaml
version: v1
plugins:
  - name: ts
    out: gen/ts
    opt:
      - nestJs=true
    path: node_modules/ts-proto/protoc-gen-ts_proto
```

sample.proto
```proto
syntax = "proto3";

package sample.v1;

service SampleService {
  rpc GetSample(GetSampleRequest) returns (GetSampleResponse) {}
}

message GetSampleRequest {
  string id = 1;
}

message GetSampleResponse {
  string id = 1;
  string name = 2;
}
```

</details>

### Additional contract requirements

- For `camelToSnake("getV1Foo")`, the result must be exactly `GET_V1_FOO`.
