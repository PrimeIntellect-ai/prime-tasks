Unable to start LSP on MacOS with ts plugin
### Describe the bug
When activating after initialising a gauge-ts project, the extensions was unable to start after repeatedly crashing.

side note:
- initialising gauge-java and gauge-js seems to work fine, but referencing gave an error `failed to parse request json: cannot unmarshal array into Go value of type string`


### What command(s) did you run when you found the bug?
Activating the extension, selecting the template for gauge-ts

### Output, stack trace or logs related to the bug

lsp.log

        14-01-2021 18:14:31.669 [Gauge] [DEBUG] Attempting to connect to grpc server at port: 57622
        14-01-2021 18:14:31.672 [Gauge] [DEBUG] Successfully made the connection with runner with port: 57622
        14-01-2021 18:14:31.672 [Gauge] [INFO] LangServer: reading on stdin, writing on stdout
        14-01-2021 18:14:31.884 [Gauge] [DEBUG] Runner with PID:61704 has exited
        14-01-2021 18:14:31.885 [Gauge] [INFO] Connection closed
        14-01-2021 18:14:31.885 [Gauge] [ERROR] Unable to log error 'Connection closed' to LSP: jsonrpc2: connection is closed

### Versions

0.0.19

#### Gauge (Output of `gauge -v`)

        Gauge version: 1.1.7
        Plugins
        -------
        html-report (4.0.12)
        java (0.7.13)
        js (2.3.15)
        screenshot (0.0.1)
        ts (0.1.0)

#### Node.js/Java/Python/.Net/Ruby version

        node --version
        v14.9.0

#### Operating System information

MacOS Big Sur
Version 11.1


#### IDE information

Visual Studio Code Version: 1.52.1

### Additional contract requirements

When an initialized Gauge TypeScript project is activated on macOS, the language server must start and remain available to handle subsequent requests rather than repeatedly crashing. Step-reference requests whose parameters are an array of step text values must be accepted, and references for the requested step must be returned.
