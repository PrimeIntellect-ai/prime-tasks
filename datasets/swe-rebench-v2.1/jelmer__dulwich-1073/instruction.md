Repo.reset_index is broken
Suppose I have a repository with a staged file:
```bash
mkdir test-repo
cd test-repo
git init
git commit --allow-empty --allow-empty-message -m ''
touch file
git add file
```

Then I reset the index using dulwich:
```python
import dulwich.repo
r = dulwich.repo.Repo('test-repo')
r.reset_index()
```

However, the index is not reset. It still contains `file`.

[HIDDEN] The documentation claims that the existing index is wiped. [HIDDEN]

### Additional contract requirements

- After `Repo.reset_index()` resets the index, staged entries that are absent from the tree being restored must no longer appear in the index.
