`verifyAndReceive` should accept raw string payload
<!-- Please replace all placeholders such as this below -->

**What happened?**
Using `verifyAndReceive` method with a payload in `string` format does not work

Details here: https://github.com/probot/probot/pull/1467#issuecomment-767944136

**What did you expect to happen?**
`verifyAndReceive` should accept the raw `payload` payload string besides the parsed object

**What the problem might be**
To improve signature of `verifyAndReceive` to support both types

### Additional contract requirements

- TypeScript callers must be able to pass either a raw JSON string payload or a parsed object payload to `verifyAndReceive` without a type cast.
