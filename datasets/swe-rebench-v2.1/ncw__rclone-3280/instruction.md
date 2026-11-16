Behaviour for HTTP API is not the same as with CLI API
<!--

Welcome :-) We understand you are having a problem with rclone; we want to help you with that!

If you've just got a question or aren't sure if you've found a bug then please use the rclone forum:

    https://forum.rclone.org/

instead of filing an issue for a quick response.

If you think you might have found a bug, please can you try to replicate it with the latest beta?

    https://beta.rclone.org/

If you can still replicate it with the latest beta, then please fill in the info below which makes our lives much easier.  A log with -vv will make our day :-)

Thank you

The Rclone Developers

-->

#### What is the problem you are having with rclone?

Sending requests that should fail (missing local dir, access denied to remote, etc.) to rclone HTTP server are not failing. They end with empty object and 200 code result. Tested with both curl and rclone rc.

Example:

```
a> rclone rcd -vv --rc-no-auth
b> rclone rc sync/move srcFs=/non-existent/ dstFs=created-but-inaccessible-remote:bucket/test
{}
b> curl --verbose -H "Content-Type: application/json" -d '{"srcFs":"local-dir-that-exists", "dstFs":"created-but-inaccessible-remote:bucket/test"}' http://localhost:5572/sync/move
*   Trying 127.0.0.1...
* TCP_NODELAY set
* Connected to localhost (127.0.0.1) port 5572 (#0)
> POST /sync/move HTTP/1.1
> Host: localhost:5572
> User-Agent: curl/7.58.0
> Accept: */*
> Content-Type: application/json
> Content-Length: 65
>
* upload completely sent off: 65 out of 65 bytes
< HTTP/1.1 200 OK
< Access-Control-Allow-Headers:
< Access-Control-Allow-Origin: *
< Date: Tue, 07 May 2019 08:11:03 GMT
< Content-Length: 3
< Content-Type: text/plain; charset=utf-8
<
{}

```

Same request made with CLI is reporting an error (with retries) and exiting with `1`. I've taken a look at the code and it seems that CLI calls are wrapped with `cmd.Run` function which integrates with `accounting` and has retries. This functionality is not available within handler for HTTP server so requests never fail. Although available in the server error logs.

Which leads me to another "API design" question, why is for example `sync.MoveDir` not returning an error on failure? It seems currently the only way to know if there was a failure is to use `accounting.Stats`. From how these top level functions are used it seems like entire call chain depends on these top level functions to return errors.

#### What is your rclone version (output from `rclone version`)

rclone v1.47.0-DEV
- os/arch: linux/amd64
- go version: go1.12.4

Ubuntu 18.04

####  Which cloud storage system are you using? (eg Google Drive)

AWS S3 but it shouldn't matter to this issue.

#### A log from the command with the `-vv` flag (eg output from `rclone -vv copy /tmp remote:tmp`)

HTTP Server logs:

```
2019/05/07 10:28:09 DEBUG : rclone: Version "v1.47.0-DEV" starting with parameters ["rclone" "rcd" "-vv" "--rc-no-auth"]
2019/05/07 10:28:09 NOTICE: Serving remote control on http://127.0.0.1:5572/
2019/05/07 10:28:14 DEBUG : rc: "sync/move": with parameters map[dstFs:bla:bucket/test srcFs:/non-existent/]
2019/05/07 10:28:14 DEBUG : Using config file from "/home/alek/.config/rclone/rclone.conf"
2019/05/07 10:28:15 ERROR : S3 bucket bucket path test/: Failed to update region for bucket: reading bucket location failed: AccessDenied: Access Denied
	status code: 403, request id: 5F13BD3082D862ED, host id: FlUy7pvhPWARqV4qVNBGRhKbrIykPXQnFAfRoU/6CK6HGs3qyWaZq/u57YLYOjqbn0yAa0WyoKM=
2019/05/07 10:28:15 ERROR : S3 bucket bucket path test/: Failed to update region for bucket: reading bucket location failed: AccessDenied: Access Denied
	status code: 403, request id: F45BAF0FA7E4A5D9, host id: SRxpFTaW90nTzWMToU5XBAeHI4lepEBM3mtTJrBwHx2L99FMQhqz2rLEtrcX+qDzKm6bcPx4u4g=
2019/05/07 10:28:15 ERROR : : error reading source directory: directory not found
2019/05/07 10:28:15 INFO  : S3 bucket bucket path test/: Waiting for checks to finish
2019/05/07 10:28:15 INFO  : S3 bucket bucket path test/: Waiting for transfers to finish
2019/05/07 10:28:15 DEBUG : rc: "sync/move": reply map[]: <nil>
2019/05/07 10:28:57 DEBUG : rc: "sync/move": with parameters map[dstFs:bla:scylla-manager-aleksandar/bash srcFs:tmp]
2019/05/07 10:28:57 ERROR : : error reading source directory: directory not found
2019/05/07 10:28:57 INFO  : S3 bucket scylla-manager-aleksandar path bash/: Waiting for checks to finish
2019/05/07 10:28:57 INFO  : S3 bucket scylla-manager-aleksandar path bash/: Waiting for transfers to finish
2019/05/07 10:28:57 DEBUG : rc: "sync/move": reply map[]: <nil>
```

### Additional contract requirements

- The public function `Check(ctx context.Context, fdst, fsrc fs.Fs, oneway bool) error` in package `fs/operations` must return a non-nil error when the source or destination filesystem cannot be accessed, for example when it points to a non-existent directory.
- The public function `CopyDir(ctx context.Context, fdst, fsrc fs.Fs, copyEmptySrcDirs bool) error` in package `fs/sync` must return a non-nil error when the source filesystem points to a non-existent directory or when copying otherwise encounters an error.
