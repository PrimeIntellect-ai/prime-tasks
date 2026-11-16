dulwich.porcelain.add() corrupts branch
Hello,

I have a repo inside c:/tmp/release-package-v0.0.1

When I run

```
local_path = 'c:/tmp/release-package-v0.0.1'
porcelain.add(local_path, local_path)
rst = status(local_path)
print(rst)
```

It shows some strange status:

`GitStatus(staged={'add': [b'./'], 'delete': [], 'modify': []}, unstaged=[], untracked=['LICENSE', 'README.md', 'synchronizer.py'])`

So my untracked files are not added to repo but some b'./' instead.

If I commit those changes, then git repository becomes corrupted and I can't run 'status' or standalone git commands inside it anymore.

It says 'Fatal: empty filename in tree'

Please help me how to add new files into repository, any working workaround will be much appreciated! It seems problem is with **relpath** in porcelain.py but I'm not sure how to fix it :(

```
        for p in paths:
            path = Path(p)
            relpath = str(path.resolve().relative_to(repo_path))
            # FIXME: Support patterns
```

Thank you!

### Additional contract requirements

- `porcelain.add(repo, paths=...)` must accept a single path string as well as a sequence of paths. If that string names the repository root, add the untracked files beneath it rather than staging the root directory as an entry.
