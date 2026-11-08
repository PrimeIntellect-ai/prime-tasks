[helm3] unknown subcommand should return error
<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

The output of `helm version`:

```
version.BuildInfo{Version:"v3.0.0", GitCommit:"e29ce2a54e96cd02ccfce88bee4f58bb6e2a28b6", GitTreeState:"clean", GoVersion:"go1.13.4"}
```

There is no error raised if I passed an unknown subcommand to Helm 3, no error message and the exit code is 0.
It's really hard to find out what is going wrong when I was debugging a helm 2 plugin. there supposed to be an error message to tell me which subcommand does not exist.

### Additional contract requirements

- When Helm is invoked with the unknown subcommand `foobar`, the error message must be exactly `unknown command "foobar" for "helm"`.
