Default HTTP API log format
# Bug Report

## Description

The default format produces a JSON log entry like this, with an extra enclosing `{}`. I'm assuming that was unintentional as I've never seen this format before:

```
{{
    "requestId": "xxxxxxxxxxxxxxxx",
    "ip": "###.###.###.###",
    "requestTime": "08/Apr/2020:19:27:25 +0000",
    "httpMethod": "GET",
    "routeKey": "GET /path",
    "status": "500",
    "protocol": "HTTP/1.1",
    "responseLength": "35"
}}
```

I'll just use a custom format instead of the default.

Relevant section of code:
https://github.com/serverless/serverless/blob/030379d15ba0700c0e705214a0b7903e1f2d52c0/lib/plugins/aws/package/compile/events/httpApi/index.js#L222
