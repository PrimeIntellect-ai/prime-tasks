Upload Path Randomness
Is there a specific security or practical reason that the component before the file name of an upload path is random? The variable names in `uploaders.py` seem to indicate that at some point this was a hash sum of the file (`md5hash`).

I ask because I'm trying to implement an automated CTF management tool which can synchronize a CTFd instance with a local configuration (defined in YAML files). The challenge definitions define file names/paths to upload, but there's no way for me to quickly check whether a file has changed, which makes it difficult to implement the sync logic.

Currently my only options are:

1. Assume the file is dirty and always delete/re-upload
2. Assume the file is clean if it exists, and require a separate option to force re-uploading.

In case one, this makes synchronizing the entire platform always take a long time (due to deleting/re-uploading every challenge attachment). Option two requires the user to remember if/when files are changed. In a distributed development environment, it would be great to allow developers to push changes to the CTFd configuration and an admin to simply synchronize the configuration.

I'm open to running a local fork of CTFd for my use-case, but I wanted to make sure there wasn't a serious reason it was implemented in this way before I just decided to change it. Thanks!

### Additional contract requirements

POST /api/v1/files accepts an optional multipart form field named `location`. A supplied location of `testing/asdf.txt` must be saved as the file's location; `testing/prefix/asdf.txt`, `/testing/asdf.txt`, and `asdf.txt` must each be rejected with HTTP 400. Uploading a file to a location already used by an uploaded file replaces the stored contents at that location. Each file record exposes `sha1sum`, the lowercase hexadecimal SHA-1 digest of its uploaded contents, and `GET /api/v1/files/<id>` includes the same digest at `data.sha1sum`. The digest for `test file content` is `9032bbc224ed8b39183cb93b9a7447727ce67f9d`, and the digest for `testing new uploaded file content` is `0ee7eb85ac0b8d8ae03f3080589157cde553b13f`.
