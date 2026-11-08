Git lfs doesn't not honor core.sharedRepository
Regression of #2992

https://github.com/git-lfs/git-lfs/pull/3304 seems to have not fixed this sadly.

attn @bk2204

Reproducibility.

```
paul@paul-Lenovo-IdeaPad-Y500:~$ sudo docker run -it --rm  --entrypoint "/bin/ash" alpine/git
/git # wget https://github.com/git-lfs/git-lfs/releases/download/v2.6.1/git-lfs-linux-amd64-v2.6.1.tar.gz
Connecting to github.com (192.30.253.112:443)
Connecting to github-production-release-asset-2e65be.s3.amazonaws.com (52.216.165.243:443)
git-lfs-linux-amd64- 100% |***********************************************************************************************************************|  3525k  0:00:00 ETA
/git # tar -zxvf git-lfs-linux-amd64-v2.6.1.tar.gz
README.md
CHANGELOG.md
git-lfs
install.sh
/git # cp git-lfs /usr/bin/
/git # git lfs install
Git LFS initialized.
/git # git config --global core.sharedrepository 0777
/git # git clone https://github.com/paulcdejean/lfs_bug.git
Cloning into 'lfs_bug'...
remote: Enumerating objects: 7, done.
remote: Counting objects: 100% (7/7), done.
remote: Compressing objects: 100% (5/5), done.
remote: Total 7 (delta 0), reused 7 (delta 0), pack-reused 0
Unpacking objects: 100% (7/7), done.
/git # ls -la lfs_bug/.git
total 56
drwxrwsrwx    9 root     root          4096 Dec  3 21:05 .
drwxr-xr-x    3 root     root          4096 Dec  3 21:05 ..
-rw-rw-rw-    1 root     root            23 Dec  3 21:05 HEAD
drwxrwsrwx    2 root     root          4096 Dec  3 21:05 branches
-rw-rw-rw-    1 root     root           330 Dec  3 21:05 config
-rw-rw-rw-    1 root     root            73 Dec  3 21:05 description
drwxrwsrwx    2 root     root          4096 Dec  3 21:05 hooks
-rw-rw-rw-    1 root     root           321 Dec  3 21:05 index
drwxrwsrwx    2 root     root          4096 Dec  3 21:05 info
drwxr-sr-x    5 root     root          4096 Dec  3 21:05 lfs
drwxrwsrwx    3 root     root          4096 Dec  3 21:05 logs
drwxrwsrwx   11 root     root          4096 Dec  3 21:05 objects
-rw-rw-rw-    1 root     root           114 Dec  3 21:05 packed-refs
drwxrwsrwx    5 root     root          4096 Dec  3 21:05 refs
/git #
```

Note that the permissions of the lfs directory don't reflect the value of `core.sharedrepository 0777` whereas the objects directory does.

### Additional contract requirements

- Git LFS must create the directories it manages, including the `.git/lfs` storage directory and its subdirectories, with permissions derived from `core.sharedRepository`, so that they match the permissions Git applies to the `objects` directory.
- Add a public method `RepositoryPermissions(executable bool) os.FileMode` on `*config.Configuration` in package `config`. It returns the repository file mode derived from `core.sharedRepository`; when `executable` is true, the returned mode has executable bits set for each readable bit.
- Add a public method `RepositoryPermissions(executable bool) os.FileMode` on `*fs.Filesystem` in package `fs`. It returns the repository file mode held by the filesystem; when `executable` is true, the returned mode has executable bits set for each readable bit.
- Add a public function `NewClient(remote string, lfsClient *lfsapi.Client, cfg *config.Configuration) (*locking.Client, error)` in package `locking`.
- Add a public function `NewMeter(cfg *config.Configuration) *tq.Meter` in package `tq`. The meter uses the configuration so that directories it creates for progress log files honor `core.sharedRepository`.
- Add a public function `ExecutablePermissions(perms os.FileMode) os.FileMode` in package `tools` that returns `perms | ((perms & 0444) >> 2)`.
