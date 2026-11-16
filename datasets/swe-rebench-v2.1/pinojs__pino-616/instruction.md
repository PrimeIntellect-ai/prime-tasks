message not taking precedence over mergedObject
I'm creating a simple wrapper around Pino like that

```
const logger = pino({
  base: null,
  messageKey: 'message'
});

export default logger;
```

And I have `jest` test like that

```
it("should log an object", () => {
    const spy = jest.spyOn(process.stdout, "write");
    logger.info({ data: 123, test: true, message: "Message from mergingObject" }, "Message");

    expect(spy).toHaveBeenCalled();

    // Get the first argument of the first call
    const argument = spy.mock.calls[0][0];
    expect(argument).toBeTruthy();

    const data = JSON.parse(argument);
    expect(data.time).toBeGreaterThan(0);
    expect(data.v).toBeGreaterThan(0);
    expect(data.level).toEqual(30);
    expect(data.message).toEqual("Message");
  });
```

This test fails because of `data.message = Message from mergingObject`. But according to the docs

> The message parameter takes precedence over the mergedObject. That is, if a mergedObject contains a msg property, and a message parameter is supplied in addition, the msg property in the output log will be the value of the message parameter not the value of the msg property on the mergedObject.

Am I missing something or is it a bug?
