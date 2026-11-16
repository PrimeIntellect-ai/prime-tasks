Multiline configmap data produces output with lines separated by empty lines
Multiline configmap data produces output with lines separated by empty lines
---------------------------------

The output of the [suggestion #86 ](https://github.com/awslabs/cdk8s/issues/86) is a little off (i.e. not pretty). For example, with the snippet below:
You will get a yaml file with empty lines in between each line in the array.
To contrast, running `console.log(daemonfile)` in TypeScript playground(/node for the compiled javascript),  the multiline output has no empty lines in between (as required).

In the end the yaml is a little chunkier than it should be. Am I missing something here?

```typescript
let daemonfile = [
            "# Maximum buffer size in MB (minimum 3). Choose 0 to use 1% of host memory. ",
            "TotalBufferSizeMB: 0",
            "# Maximum number of concurrent calls to AWS X-Ray to upload segment documents.",
            "Concurrency: 8",
            "# Send segments to AWS X-Ray service in a specific region",
            "Region: \"\"",
            "# Change the X-Ray service endpoint to which the daemon sends segment documents.",
            "Endpoint: \"\"",
            "Socket:",
            "  # Change the address and port on which the daemon listens for UDP packets containing segment documents.",
            "  # Make sure we listen on all IP's by default for the k8s setup",
            "  UDPAddress: 0.0.0.0:2000",
            "Logging:",
            "  LogRotation: true",
            "  # Change the log level, from most verbose to least: dev, debug, info, warn, error, prod (default).",
            "  LogLevel: prod",
            "  # Output logs to the specified file path.",
            "  LogPath: \"\"",
            "# Turn on local mode to skip EC2 instance metadata check.",
            "LocalMode: false",
            "# Amazon Resource Name (ARN) of the AWS resource running the daemon.",
            "ResourceARN: \"\"",
            "# Assume an IAM role to upload segments to a different account.",
            "RoleARN: \"\"",
            "# Disable TLS certificate verification.",
            "NoVerifySSL: false",
            "# Upload segments to AWS X-Ray through a proxy.",
            "ProxyAddress: \"\"",
            "# Daemon configuration file format version.",
            "Version: 1"
        ].join("\n");

        new ConfigMap(scope, "xray-config", {
            data: {
                "config.yaml": daemonfile
            }
        });
```

I also tried with the another pattern, i.e. using a back tick **`** e.g.
The output wasn't any better:

``` TypeScript
let daemonfile = `
line1
line2
...
`
new ConfigMap(scope, "xray-config", {
            data: {
                "config.yaml": daemonfile
            }
        });
```

I could not get away with trying regex to replace new lines as well, e.g.
``` TypeScript
const regex = new RegExp("\n{2,}",'gi');
let daemonfile = [
            "# Maximum buffer size in MB (minimum 3). Choose 0 to use 1% of host memory. ",
            "TotalBufferSizeMB: 0",
            "# Maximum number of concurrent calls to AWS X-Ray to upload segment documents.",
            "Concurrency: 8",
            "# Send segments to AWS X-Ray service in a specific region",
            "Region: \"\"",
...
]
].join("\n").replace(regex, "");

new ConfigMap(scope, "xray-config", {
            data: {
                "config.yaml": daemonfile
            }
        });
```

### Additional contract requirements

- When serializing YAML, ordinary string values are not automatically double-quoted: for example, `foo: "bar"` is emitted as `foo: bar`. A value such as `foo: "on"` remains quoted, and `bar: "this has a \"big quote\""` is emitted as `bar: this has a \"big quote\"`.
- Multiline string data in a ConfigMap is emitted with its content on consecutive YAML lines, without blank lines between those lines, and the serialized YAML preserves the original string value.
