Confusing behaviour with trailing `/` in destination
### What happened?

I have the following nfpm.yaml:

```yml
name: foo
version: 0.0.0
maintainer: asdf
arch: amd64
contents:
- dst: /usr/local/share/file/
  src: file.txt
```

Note the `/` at the end of the destination path. Because of that, I expect nfpm to install the file as `/usr/local/share/file/file.txt`. However, it installs the file as `/usr/local/share/file`. This is confusing because the trailing `/` indicates that the path is a directory, so the logical course of action would be to put the file into the directory.

### How can we reproduce this?

Copy the above nfpm.yaml, and create a file `file.txt`, and run `nfpm package -p deb`

### nfpm version

```bash
nfpm version nfpm version 2.22.0
commit: 5c3cc38943f1743bcaeb422c2dc65555fc9b12a1
built at: 2022-11-12T03:50:16Z
built by: goreleaser
module version: v2.22.0, checksum: h1:TC6tuxxFq0hL0WapI63+CkLMbcsYRbR7kAnLkRYAEbo=
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_
