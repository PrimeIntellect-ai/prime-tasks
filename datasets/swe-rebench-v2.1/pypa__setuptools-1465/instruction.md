40.1.0 breaks version detection on some packages
Hello;

I tried updating setuptools to 40.1.0 in the BuildRoot project, only to find a few packages such as
python-cryptography no longer seem to think setuptools is a version high enough to work.
Another package that has the same issue is python-funcsigs as well.

Downgrading to 40.0.0 fixes the issue.  Any idea as to what could be going on?

Thanks!

### Additional contract requirements

- For a project with version `0.0.0`, running `egg_info` with `[egg_info]` settings `tag_build = dev`, `tag_date = 0`, and `tag_svn_revision = 0` must produce a `PKG-INFO` line exactly equal to `Version: 0.0.0.dev0`.
