Payload as Content-Type text/plain as argument to script
Hi,

I'm trying to configure webhook to also send a payload, configured as text/plain to my script.

I got the following hooks.json
```
[
        {
                "id": "testHook",
                "execute-command": "/var/script/test.sh",
                "command-working-directory": "/my/working/dir",
                "pass-arguments-to-command": [
                        {
                                "source": "entire-payload"
                        }
                ]
        }
]
```
My test.sh is just:
```
#!/bin/sh

PARAM=$1

echo "Test Texecuted"
echo "Param: "
echo $PARAM
```
If I send a payload like {"test": "test2"} I get the desired output.

But if I send this payload as a content-type text/plain, only null is passed. The problem is, I can get JSON-conform payloads as well as payloads that are just a string. I only want to pass the complete payload to my script, is that somehow possible? Thanks in advance!

### Additional contract requirements

- Support `raw-request-body` as a `pass-arguments-to-command` source. It passes the complete HTTP request body to the command as one argument, including when the request has `Content-Type: text/plain`.
