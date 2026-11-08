Misleading Error Message On Deployment Error
### Issue To Be Solved

I was trying to deploy a contract to testnet using `flow project deploy --network=testnet`. However, I accidentally omitted the "testnet" field in my JSON structure.

I.e. the deployments section of my `flow.json` looked like:

```json
"deployments": {
    "example-account": ["ExampleContract"]
}
```
instead of:

```json
"deployments": {
    "testnet": {
        "example-account": ["ExampleContract"]
    }
}
```

However, when I ran `flow project deploy --network=testnet` I received the error:

![](https://cdn.discordapp.com/attachments/621847426201944074/882491160042561546/Screen_Shot_2021-09-01_at_1.04.32_AM.png)

However, I did have a `flow.json` in the root of my project, and so of course running `flow init` fails.

### (Optional): Suggest A Solution

This was totally my fault, the JSON that I had in my `flow.json`, while valid JSON structurally, did not contain all of the requirements that Flow CLI required. However, I think that the error message here is lacking a bit as this took a while for me to find what was going on.

I would suggest a more specific error message if Flow CLI parses the JSON for a certain attribute and does not find it, that should likely be reported, instead of reporting that the entire config file is missing.

### Additional contract requirements

- When loading a JSON configuration whose `deployments` object maps `emulator-account` to an object containing `address` and `key` fields, return exactly `configuration syntax error: json: cannot unmarshal string into Go struct field jsonConfig.deployments of type []json.deployment`.
