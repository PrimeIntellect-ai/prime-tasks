3.1 environment credentials always return __PWRD__ placeholder
### Current Behavior

Upgraded from 3.0.2 to 3.1.0.

* Projects feature is enabled.
* `editorTheme.header.title` added with some info text
* `apiMaxLength: '32mb'`
* other than that default configuration with some extra nodes installed.
* Running nodered/node-red:latest Docker image.

### Tried to add environment credentials like this:
![image](https://github.com/node-red/node-red/assets/3417983/059f0be4-893e-4c27-a063-977754fe6798)

### And then use it like this:
![image](https://github.com/node-red/node-red/assets/3417983/17e0d450-9a5d-4e19-89c2-f86d3ade33b0)
```json
[{"id":"5fc48ad328d81f1b","type":"inject","z":"d005e303e68c6631","name":"","props":[{"p":"payload"}],"repeat":"","crontab":"","once":false,"onceDelay":0.1,"topic":"","payload":"SOMETHING","payloadType":"env","x":790,"y":600,"wires":[["d38f2ec5e2d6f967"]]},{"id":"d38f2ec5e2d6f967","type":"debug","z":"d005e303e68c6631","name":"debug","active":true,"tosidebar":true,"console":false,"tostatus":false,"complete":"payload","targetType":"msg","statusVal":"","statusType":"auto","x":950,"y":600,"wires":[]}]
```

This always results in string `__PWRD__` which AFAIK is placeholder for credentials, doesn't seem to be actually reading credentials at all but just returns placeholder.

### Expected Behavior

Env variable should return `qwerty` instead of `__PWRD__`.

### Steps To Reproduce

Route I took to hit this issue:
1. Have projects enabled on 3.0.2 (I'd assume using projects might affect outcome).
2. Upgrade to 3.1
3. Add some credentials to global environment.
4. Try to use those credentials.

### Example flow

_No response_

### Environment

- Node-RED version: v3.1.0
- Node.js version: v16.20.2 (comes with official Docker image)
- npm version: 8.19.4 (comes with official Docker image)
- Platform/OS: Docker nodered/node-red:latest on debian host.
- Browser: Chrome 118

### Additional contract requirements

- The Flow runtime must resolve the environment variables of a `global-config` node even when `credentials.get(id)` returns `null`/`undefined` for that node (i.e. the node has no stored credentials). For example, a `global-config` node with env `{"name":"GC1","value":"5+6","type":"jsonata"}` and no stored credentials resolves `GC1` to `11`.
