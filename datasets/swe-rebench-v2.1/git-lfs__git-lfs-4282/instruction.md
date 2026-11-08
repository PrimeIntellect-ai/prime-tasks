Proxy URL does not use default ports if omitted
**Describe the bug**
In our setup the LFS server returns URLs containing the port (HTTPS, Port 443). If they are matched against URLs from the git config they don't match because the git config omits the port while the URL from the server does not. This behavior does not match the one described in rule 3 in the [git documentation](https://git-scm.com/docs/git-config#Documentation/git-config.txt-httplturlgt).

The relevant comparison is done here: https://github.com/git-lfs/git-lfs/blob/effc2b1b64c9594f0159f14f5214fa7470e62596/config/url_config.go#L116
And I think the problem is with the `net.url.Port()` which returns an empty string for a missing port instead of the default port for said scheme (see https://golang.org/pkg/net/url/#URL.Port)

Introduced in #3392.

**To Reproduce**
Steps to reproduce the behavior:
1. Use `GIT_TRACE=1 git lfs fetch` to examine the advertised URLs from your test server.
2. Define a global proxy server that DOES NOT WORK (something like localhost) using `http.proxy=localhost`
3. Test that a `GIT_TRACE=1 git lfs fetch` fails with the config
4. Add an exception for the proxy. If your server includes the proxy, omit it here, otherwise include the default proxy for the scheme:
   `git config http.<url>.proxy ''`
5. `GIT_TRACE=1 git lfs fetch` will fail
6. `git config --get-urlmatch http.proxy <url from step 1>` returns the correct proxy (None) and not the proxy from step 2

Example with my setup:
1. Server response: `https://my.company.int:443/artifactory/repo/objects/...`
2. `git config http.proxy localhost`
3. It doesn't work
4. `git config http.https://my.company.int/.proxy ''`
5. Still fails
6. `git config --get-urlmatch http.proxy https://my.company.int:443` -> empty (expected)

**Expected behavior**
Both LFS and git should have the same behavior.

**System environment**
Not relevant

**Output of `git lfs env`**

```
git-lfs/2.12.0 (GitHub; windows amd64; go 1.14.7; git dad7b9e6)
git version 2.28.0.windows.1

Endpoint=https://my.company.int/artifactory/repo (auth=none)
  SSH=my.company.int:artifactory/repo
Endpoint (origin_https)=https://my.company.int/artifactory/api/lfs/repo (auth=basic)
LocalWorkingDir=C:\repo
LocalGitDir=C:\repo\.git
LocalGitStorageDir=C:\repo\.git
LocalMediaDir=C:\repo\.git\lfs\objects
LocalReferenceDirs=
TempDir=C:\repo\.git\lfs\tmp
ConcurrentTransfers=8
TusTransfers=false
BasicTransfersOnly=false
SkipDownloadErrors=false
FetchRecentAlways=false
FetchRecentRefsDays=7
FetchRecentCommitsDays=0
FetchRecentRefsIncludeRemotes=true
PruneOffsetDays=3
PruneVerifyRemoteAlways=false
PruneRemoteName=origin
LfsStorageDir=C:\repo\.git\lfs
AccessDownload=none
AccessUpload=none
DownloadTransfers=basic,lfs-standalone-file
UploadTransfers=basic,lfs-standalone-file
GIT_CURL_VERBOSE=1
GIT_EXEC_PATH=C:/Program Files/Git/mingw64/libexec/git-core
GIT_LFS_PATH=C:\Program Files\Git LFS
GIT_TRACE=0
GIT_TRANSFER_TRACE=1
git config filter.lfs.process = "git-lfs filter-process"
git config filter.lfs.smudge = "git-lfs smudge -- %f"
git config filter.lfs.clean = "git-lfs clean -- %f"
```
