`helm repo add` is missing --password-stdin
**What**

You currently can't pipe the password into `helm repo add`:

```
$ echo password | helm repo add repo-name https://repo-url --username username
Password:
Error: inappropriate ioctl for device
```

I would expect the option `--password-stdin` to be available:

```
$ echo password | helm repo add repo-name https://repo-url --username username --password-stdin
"repo-name" has been added to your repositories
```

**Why**

There are two reasons I see for adding this:

* I personally would expect that it's possible to pipe the password into
  `helm repo add` but that's currently not the case. If I understand it
  correctly, you currently either need to pass the password via a cli
  parameter (`--password`) or use a expect/send mechanism. The
  cli parameter mechanism also isn't secure as it might expose the
  password via the process name.

* Subcommands like `helm registry login` already support
  `--password-stdin`. The cli interfaces should be consistent regarding
  which options they support.
