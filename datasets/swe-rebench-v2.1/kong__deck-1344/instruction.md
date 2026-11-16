render adding "regex_priority" key to expression route resulting sync to fails
Kong file render generates legacy route "regex_priority" key when expression routes are used resulting that rendered file validation fails and file cannot be synched, resulting error

```
Error: 1 errors occurred:
        while processing event: Update route debug_node_log-level failed: HTTP status 400 (message: "schema violation (regex_priority: unknown field)")
```
repro steps

Kong version 3.6.1.1, deck 1.35, linux

create declarative config with single service/route/plugin pointing to Kong itself
```
services:
# debug
- host: localhost
  name: debug_node_log-level
  port: 8001
  protocol: http
  routes:
  - expression: (net.protocol == "http") && (http.method == "GET") && (http.path ==
      "/api/debug/node/log-level")
    name: debug_node_log-level
  priority: 100
plugins:
- config:
    replace:
      uri: /debug/node/log-level
  name: request-transformer
  route: debug_node_log-level
```

render the declarative configuration.

deck file render kong-common*.yaml merge-routes.yaml -o render-kong-deck.yaml
deck file merge kong-common*.yaml merge-routes.yaml -o merge-kong-deck.yaml

rendered file contains "regex_priority" which is used with legacy routes.

```
- connect_timeout: 60000
  host: localhost
  name: debug_node_log-level
  port: 8001
  protocol: http
  read_timeout: 60000
  routes:
  - expression: (net.protocol == "http") && (http.method == "GET") && (http.path ==
      "/api/dbf/ca/debug/node/log-level")
    name: debug_node_log-level
    plugins:
    - config:
        replace:
          uri: /debug/node/log-level
      name: request-transformer
    preserve_host: false
    priority: 100
    protocols:
    - http
    - https
    regex_priority: 0 # this is not valid key in expression route
    strip_path: true
    tags:
    - debug

```
Validation of rendered file fails.
Rendered file cannot be used to sync with Kong.

Merged file can be synched because it does not contain regex_priority key

Workaround - use kong deck patch to remove invalid key
cat render-kong-deck.yaml | deck file patch --selector="$..routes[*]" --value="regex_priority:" -o render-kong-deck.yaml

### Additional contract requirements

- Rendering expression-based routes must omit the `regex_priority` field. Rendering traditional routes must continue to include `regex_priority` as before.
