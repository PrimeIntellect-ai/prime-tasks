fetchexclude configuration interferes with git lfs ls-files
Let me begin by saying thank you for this great tool: I just started using it and it seems to work very smoothly. Thank you!

I'm not sure if what I'm describing here is actually a bug or if it is an intentional feature. If this is expected behavior, feel free to close this issue.

**Describe the bug**

Based on comments in #2717  I introduced a `.lfsconfig` file in my repository with the following contents:

```
[lfs]
        fetchexclude = *
```

The purpose is: We are using git-lfs to manage some image files in our repository, but it in > 99% of cases, people cloning the repository don't need these images, so we want to configure git-lfs to not download these large files when cloning / fetching. (If someone needs them, they will obtain them with `git lfs pull --exclude=""`.)

This seems to work as intended, but a side effect is that, if I run:

```
git lfs ls-files
```

nothing is shown.

**To Reproduce**

I have reproduced this by following the first section of https://github.com/git-lfs/git-lfs/wiki/Tutorial ("Create a new repo"). At the end of those instructions, `git lfs ls-files` works as expected.

Then introduce a file named `.lfsconfig` at the top level of the repository, with contents:

```
[lfs]
        fetchexclude = *
```

Rerun `git lfs ls-files` and observe that nothing is printed.

**Expected behavior**

I expected `git lfs ls-files` to operate the same regardless of my `fetchexclude` configuration, since that configuration name implies that it just applies to fetching, not to other git-lfs operations.

**System environment**

Mac OS 10.14.6.

git version 2.25.2

Also reproduced on linux with git version 2.22.

**Output of `git lfs env`**

```
git-lfs/2.10.0 (GitHub; darwin amd64; go 1.13.6)
git version 2.25.2

LocalWorkingDir=/Users/sacks/temporary/testlfs_again
LocalGitDir=/Users/sacks/temporary/testlfs_again/.git
LocalGitStorageDir=/Users/sacks/temporary/testlfs_again/.git
LocalMediaDir=/Users/sacks/temporary/testlfs_again/.git/lfs/objects
LocalReferenceDirs=
TempDir=/Users/sacks/temporary/testlfs_again/.git/lfs/tmp
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
LfsStorageDir=/Users/sacks/temporary/testlfs_again/.git/lfs
AccessDownload=none
AccessUpload=none
DownloadTransfers=basic,lfs-standalone-file
UploadTransfers=basic,lfs-standalone-file
FetchExclude=*
GIT_EXEC_PATH=/usr/local/Cellar/git/2.25.2/libexec/git-core
GIT_PS1_SHOWDIRTYSTATE=1
GIT_PS1_SHOWUPSTREAM=auto
git config filter.lfs.process = "git-lfs filter-process"
git config filter.lfs.smudge = "git-lfs smudge -- %f"
git config filter.lfs.clean = "git-lfs clean -- %f"
```
