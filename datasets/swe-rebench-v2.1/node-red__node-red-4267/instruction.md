File nodes output error when number is specified as filename
### Current Behavior

File nodes only support string type as the file name in `msg.` and JSONata expression.
Therefore, users often encounter the following error when using timestamp for filename.

<img width="1357" alt="Screenshot 2023-08-06 at 20 49 52" src="https://github.com/node-red/node-red/assets/20310935/16de5aa0-5df7-482c-825c-e5fd6f23f820">

I thought that file nodes should support not only string but also number and boolean as filename.

### Expected Behavior

The file node stores the data in the file that has numbers as its filename.

### Steps To Reproduce

1. Put inject node
2. Put write file node
3. Open the write file node property and specify `msg.payload` as a filename.
4. Connect nodes by wire
5. Click the deploy button
6. Click the button on inject node.

### Example flow

```
[{"id":"7a37368e4713e725","type":"inject","z":"48e50bbaa6a50483","name":"","props":[{"p":"payload"},{"p":"topic","vt":"str"}],"repeat":"","crontab":"","once":false,"onceDelay":0.1,"topic":"","payload":"","payloadType":"date","x":260,"y":40,"wires":[["b3a0d920dedc5559"]]},{"id":"b3a0d920dedc5559","type":"file","z":"48e50bbaa6a50483","name":"","filename":"payload","filenameType":"msg","appendNewline":false,"createDir":false,"overwriteFile":"false","encoding":"none","x":280,"y":120,"wires":[[]]}]
```


### Environment

- Node-RED version: v3.1.0-beta.4
- Node.js version: v20.2.0
- npm version: v9.6.6
- Platform/OS: macOS Ventura 13.4.1 (c) on MacBook Air (M1, 2020)
- Browser: 115.0.5790.170 (Official Build) (arm64)
