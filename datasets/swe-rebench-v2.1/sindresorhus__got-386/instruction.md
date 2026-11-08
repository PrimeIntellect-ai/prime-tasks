Custom agent + redirects
I'm seeing the following error:
```
Uncaught error: Error: Protocol "https:" not supported. Expected "http:"
         at get (/var/app/current/node_modules/got/index.js:33:18)
         at ClientRequest.fn.request.res (/var/app/current/node_modules/got/index.js:51:5)
```

I think this is caused by passing in a custom agent (from `agentkeepalive`).
1. HTTP and HTTPS require different agent instances
2. If the initial request is HTTP we pass in the HTTP agent
3. If this request then redirects to an HTTPS url, got will still use the HTTP custom agent

Is there a way that we could pass in both an HTTP and HTTPS agent and let got handle the selection of the proper agent? Or alternatively to intercept the redirect and change the agent that will be used?

### Additional contract requirements

- The `agent` option accepted by the exported `got` function may be an object with an `http` key and/or an `https` key, each mapping to the corresponding `http.Agent` or `https.Agent` instance. A map containing only one of the two keys is valid.
- When a request redirects to a URL with a different protocol, the agent used for the redirected request is the one from the `agent` object matching the new protocol.
