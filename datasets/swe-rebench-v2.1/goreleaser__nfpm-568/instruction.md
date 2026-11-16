archlinux packager does not support folders for configs
### What happened?

Tried to create archpackage with the following configuration and failed:

```yaml
$ cat foo.yaml
name: test

contents:
- src: etc/foo
  dst: /etc/foo
  type: config
```

```sh
mkdir -p etc/foo
touch etc/foo/foo.yml
```

### How can we reproduce this?

```
$ nfpm package --target . --config foo.yaml --packager archlinux
using archlinux packager...
read etc/foo: is a directory
```

Though debian is OK:

```
$ nfpm package --target . --config foo.yaml --packager deb
using deb packager...
DEPRECATION WARNING: Leaving the 'maintainer' field unset will not be allowed in a future version
created package: test_0.0.0~rc0_amd64.deb
```

### nfpm version

```bash
nfpm version nfpm version v2.20.0
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_
