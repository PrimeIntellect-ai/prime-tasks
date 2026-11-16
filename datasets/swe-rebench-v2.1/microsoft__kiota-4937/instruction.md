We shouldn't delete the declarativeCopilot node when adding the plugins node in the manifest.json
When creating a plugin, we are adding the plugins node if there is a manifest.json file in the output directory.

I have created a declarative copilot using TTK, which creates the project with a declarativeCopilot.json and a manifest.json files.
The manifest.json is created with the following copilotExtension node:

```jsonc
"copilotExtensions": {
        "declarativeCopilots": [
            {
                "id": "declarativeCopilot",
                "file": "declarativeCopilot.json"
            }
        ]
}
```

However, when Kiota is creating the plugin, its replace the above with the following:

```jsonc
"copilotExtensions": {
        "plugins": [
            {
                "id": "myplugin",
                "file": "myplugin-apiplugin.json"
            }
        ]
}
```

The expected behaviour would be to keep what is in it, and add the plugins node:

```jsonc
"copilotExtensions": {
        "declarativeCopilots": [
            {
                "id": "declarativeCopilot",
                "file": "declarativeCopilot.json"
            }
        ],
        "plugins": [
            {
                "id": "myplugin",
                "file": "myplugin-apiplugin.json"
            }
        ]
}
```

Also, if there is already a plugin node like the above, when adding another plugin to the same project, the expected behavior is the following:

```jsonc
"copilotExtensions": {
        "declarativeCopilots": [
            {
                "id": "declarativeCopilot",
                "file": "declarativeCopilot.json"
            }
        ],
        "plugins": [
            {
                "id": "myplugin",
                "file": "myplugin-apiplugin.json"
            },
            {
                "id": "anotherplugin",
                "file": "anotherplugin-apiplugin.json"
            }
        ]
}
```
