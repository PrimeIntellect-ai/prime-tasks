Post backup scripts in v1.0
Hi,

We recently updated to the RCs of v1 and I can't seem to get post backup scripts to execute anymore.

Looking at dump.go, I'm not sure if it's a typo, but [HIDDEN]. Is this right?

https://github.com/databacker/mysql-backup/blob/1682a343c3c85caa42b26e92da7dc42baf99c10b/cmd/dump.go#L182

Thanks.

### Additional contract requirements

- The post-backup scripts configured by the user must be used for post-backup execution, independently of the configured pre-backup scripts.
