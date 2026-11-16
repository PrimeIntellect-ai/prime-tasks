Bug on Item.get, where unneeded properties are required
Today I upgraded from v0.9.2 to 0.9.3 and I noticed my test suite failed. After some debugging I found out that on every Item.get command all items that have the `required` and `dependsOn` attribute AND are missing on my Item.get command, trigger an error.

Example:
I have an Item called `Meeting` with a PK and SK, as well as some other attributes. Two of them are:
```
    status: { type: "string", map: "F12", required: true },
    statusNumber: { type: "number", map: "F16", required: true, onUpdate: true, dependsOn: "status", default: ({status}) => processStatus(status) },
```

To retrieve a record of this type all I need is a PK and SK, nothing more. However, all my `Meeting.get` calls fail because I have not provided a status (which is not needed at all in this case). I understand that this check is good for updates or creates, but is not needed for Scan, Query or Get commands.

This issue is introduced in v0.9.3.
