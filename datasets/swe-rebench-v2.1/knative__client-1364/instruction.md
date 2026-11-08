can no longer force a re-download of an image via "kn update" w/o extra stuff
Before v0.21.0 I used to be able to do:
```
$ kn service update echo --image duglin/echo
```
and it would always force a new revision to be created. This was really handy when all I wanted was for the image to be re-downloaded because I did a "docker build" to update it. Notice, I don't have a tag on the image name.

It would be nice if this feature was added back in. W/o it, it's not clear to me how to force this to happen.... at least not w/o some (non-obvious to a newbie) hack, like specifying a revision name or adding `--env foo=$RANDOM` to the cmd line.

### Additional contract requirements

- The `client.knative.dev/updateTimestamp` annotation is set on the revision template whenever a new revision is triggered: on `kn service create`, and on any `kn service update` that changes at least one revision-affecting flag (such as `--image`, `--env`, `--annotation`, `--label`, `--scale`, ...). The `kn service apply` command does not set this annotation, so that repeated applies stay idempotent. The annotation value is the current UTC time formatted as RFC3339.
