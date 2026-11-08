`DVC_SITE_CACHE_DIR` environment variable does not override `.dvc/config` settings
# Bug Report


## Description

The documentation on [environment variables](https://dvc.org/doc/user-guide/env#environment-variables) says:
>  DVC_SITE_CACHE_DIR: Directory for the [site cache dir](https://dvc.org/doc/user-guide/project-structure/internal-files#site-cache-dir). Overrides [dvc config core.site_cache_dir](https://dvc.org/doc/command-reference/config).

However, this is not working as expected and if `core.site_cache_dir` is set in `.dvc/config`, the environment variable is ignored.

### Reproduce

Setup repo with `site_cache_dir` configuration:
```console
mkdir test_repo
cd test_repo
dvc init --no-scm
dvc config core.site_cache_dir /tmp/not_this_dir/
```

Check information:
```console
$ env DVC_SITE_CACHE_DIR=/tmp/use_this_dir/ dvc doctor
DVC version: 3.60.0 (conda)
---------------------------
Platform: Python 3.10.18 on macOS-15.5-x86_64-i386-64bit
Subprojects:
        dvc_data = 3.16.10
        dvc_objects = 5.1.1
        dvc_render = 1.0.2
        dvc_task = 0.40.2
        scmrepo = 3.3.11
Supports:
        gdrive (pydrive2 = 1.21.3),
        http (aiohttp = 3.9.5, aiohttp-retry = 2.9.1),
        https (aiohttp = 3.9.5, aiohttp-retry = 2.9.1),
        s3 (s3fs = 2025.5.1, boto3 = 1.37.3),
        ssh (sshfs = 2025.2.0)
Config:
        Global: /Users/rgoya/Library/Application Support/dvc
        System: /Library/Application Support/dvc
Cache types: <https://error.dvc.org/no-dvc-cache>
Caches: local
Remotes: None
Workspace directory: apfs on /dev/disk1s5s1
Repo: dvc (no_scm)
Repo.site_cache_dir: /tmp/not_this_dir/repo/c58163f0b6f80c77503e8859c67a9713
```

### Expected

The documentation states that `DVC_SITE_CACHE_DIR=/tmp/use_this_dir/` should override the config, so the last line should have read:
```console
Repo.site_cache_dir: /tmp/use_this_dir/repo/c58163f0b6f80c77503e8859c67a9713
```

### Additional contract requirements

When `DVC_SITE_CACHE_DIR` is not set, a configured `core.site_cache_dir` remains the base location for the repository site-cache directory.
