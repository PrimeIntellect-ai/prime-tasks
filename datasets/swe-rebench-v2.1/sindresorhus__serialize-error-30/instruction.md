Consider making common error properties non enumerable
## Description

Native JS errors don't have its properties enumerable. What this means is that the `name`, `stack` and `message` properties do not appear when console.logging errors.

Notice the `name` and `message` property appearing below.

![image](https://user-images.githubusercontent.com/25233379/81183679-bf509700-8faf-11ea-8499-ee5f5608aad5.png)

## Proposal

To get deserialized errors closer to the native ones, when deserializing the error, we could use [HIDDEN] instead of a direct assignment to make the properties not enumerable. eg: here [HIDDEN]

[HIDDEN]

I'm happy to make a PR if you agree with the proposal!

Thanks for your awesome work across the Node community ❤️

### Additional contract requirements

- When deserializing an error, its `name`, `stack`, and `message` properties must be non-enumerable.
