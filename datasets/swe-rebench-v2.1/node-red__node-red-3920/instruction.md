CSV node does not cope with single quote characters in property names
### Current Behavior

If an array of objects is passed to the CSV node and it is configured to generate headers then, if any of the properties includes a single quote character, then it fails with errors like
Error: Invalid property expression: unexpected array expression at position 12

Confirmed by @TotallyInformation in https://discourse.nodered.org/t/csv-node-does-not-cope-with-quotes-in-property-names-bug-or-feature/69027

### Expected Behavior

It should not fail

### Steps To Reproduce

Run the example flow below

### Example flow

```
[{"id":"0a117283c6ec0e9a","type":"inject","z":"c57d82f577bb37d5","name":"","props":[{"p":"payload"},{"p":"topic","vt":"str"}],"repeat":"","crontab":"","once":false,"onceDelay":0.1,"topic":"","payload":"[{\"a'a\":\"A1\",\"b\":\"B1\"},{\"a'a\":\"A2\",\"b\":\"B2\"}]","payloadType":"json","x":160,"y":460,"wires":[["e9b9c226cb22fc89"]]},{"id":"e9b9c226cb22fc89","type":"csv","z":"c57d82f577bb37d5","name":"","sep":",","hdrin":"","hdrout":"all","multi":"one","ret":"\\n","temp":"","skip":"0","strings":true,"include_empty_strings":"","include_null_values":"","x":330,"y":460,"wires":[["8a79b816b21ebf6f"]]},{"id":"8a79b816b21ebf6f","type":"debug","z":"c57d82f577bb37d5","name":"debug 28","active":true,"tosidebar":true,"console":false,"tostatus":false,"complete":"false","statusVal":"","statusType":"auto","x":500,"y":460,"wires":[]}]```
```

### Environment

- Node-RED version: 3.2.0
- Node.js version: 16.17.1
- npm version: 8.15.0
- Platform/OS: Ubuntu
- Browser: Chrome
