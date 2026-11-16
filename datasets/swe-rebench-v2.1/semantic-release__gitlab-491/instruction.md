Generic package from registry can't be extracted
Hi everyone 👋

I'm using GitLab registry to push an asset with the format `gzip compressed data` (.tar.gz) but when I download the uploaded package, I can't decompress it.

Follow my `.releaserc.yml`

```yaml
branches:
  - "main"
plugins:
  - "@semantic-release/commit-analyzer"
  - "@semantic-release/release-notes-generator"
  - - "@semantic-release/exec"
    - verifyConditionsCmd: 'tar -czf package.tar.gz --exclude=".git*" --exclude="__pycache__" aws/'
  - - "@semantic-release/gitlab"
    - assets:
        - path: "package.tar.gz"
          filepath: "/package.tar.gz"
          label: "package.tar.gz"
          target: generic_package
          status: default
tagFormat: ${version}
```

If we do a `cat` to the package file, we will see weird data on top and at the end of the file.

```bash
❯ cat package.tar.gz
----------------------------636039438515691214353669
Content-Disposition: form-data; name="file"; filename="aws.tar.gz"
Content-Type: application/gzip

<REDACTED BINARY DATA>
----------------------------636039438515691214353669--
```

If we remove the first 4 files from the file with the command `sed -e '1,4d' < package.tar.gz > package2.tar.gz`, we will decompress it.

If we compress the file manually, upload it, and download it after we can decompress it since the data are been untouched.

Can someone give any insight?
