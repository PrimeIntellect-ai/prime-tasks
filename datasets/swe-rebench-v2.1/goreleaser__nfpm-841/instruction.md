Invalid dpkg-sig file
### What happened?

NFPM creates invalid dpkg-sig file, containing native byte slice string representations for hashes (instead of hex-encoded strings) and does not contain newlines between file lines. E.g.:
```
Hash: SHA1

Version: 4
Signer:
Date: 2024-07-09 07:18:57.751051895 +0000 UTC
Role: builder
Files:
[60 249 24 39 47 250 93 225 149 117 45 115 243 218 62 94] [121 89 201 105 224 146 242 165 168 96 78 34 135 128 122 197 177 179 132 173] 4 debian-binary[38 54 153 155 140 232 9 110 215 199 15 165 27 135 187 209] [94 8 122 215 206 198 28 95 108 189 249 33 180 125 163 156 241 131 41 92] 1311 control.tar.gz[86 193 58 25 7 246 222 53 69 246 157 91 0 159 228 155] [132 2 109 37 200 108 41 165 81 241 32 124 19 145 12 230 0 201 210 99] 74031244 data.tar.gz
```

Correct dpkg-sig file should look like this:

```
Hash: SHA512

Version: 4
Signer: Docker Release (CE deb) <docker@docker.com>
Date: Tue Jun 25 08:43:07 2024
Role: builder
Files:
    3cf918272ffa5de195752d73f3da3e5e 7959c969e092f2a5a8604e2287807ac5b1b384ad 4 debian-binary
    81f84b4c6811bb42e8cd2fb442fb3ad0 e1b9fa01878f05c32e6a77df93c1b7a8cf2e2641 664 control.tar.xz
    0b02e196efc352a616d22ada33c31b98 173881a95119d07459cf21a17fff6b42b9e208d9 12496204 data.tar.xz
```


### How can we reproduce this?

Create a debian package using NFPM with enabled dpkg-sig signing:

```yaml
deb:
    signature:
      method: dpkg-sig
      key: key.gpg
      type: builder
```

### nfpm version

```bash
v2.38.0
```


### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

_No response_
