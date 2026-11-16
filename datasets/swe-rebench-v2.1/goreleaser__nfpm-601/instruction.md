Platform field variable expansion not happening
### What happened?

I was creating packages, using a template with some fields:

```
name: "nerdctld"
arch: "${GOARCH}"
platform: "${GOOS}"
version: "${VERSION}"
...
```

Everything looked fine, but it turns out the rpm was invalid:

```
package nerdctld-0:0.2.1-1.x86_64 is intended for a different operating system
```

rpm --xml shows why:
```xml
  <rpmTag name="Os">
	<string>${GOOS}</string>
  </rpmTag>
  <rpmTag name="Arch">
	<string>x86_64</string>
  </rpmTag>
```

The deb package is fine, seems like it doesn't even use platform ?

(it is supposed to go in the `Architecture` field for deb, like darwin-amd64, default is linux)

### How can we reproduce this?

Try to use environment variables for platform and arch...
See that they are only expanded for arch, not for platform.

### nfpm version

```bash
nfpm version nfpm version 2.23.0
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

My workaround is to comment out the "platform", for now.

```
arch: "${GOARCH}"
#platform: "${GOOS}"
version: "${VERSION}"
```

Since the software I am packaging is linux-only, anyway...

But I can submit a test case and a patch, simple one-liner.
