Deleting files produces empty commits
**Describe the bug**
Deleting a file produces empty commits instead of deleting them

**To Reproduce**

Run the following command on a test repository containing a `README.md` (you can fork [mine](https://github.com/klieret/multi-gitter-delete-bug-demonstration)):

```bash
multi-gitter run "rm README.md" -R klieret/multi-gitter-delete-bug-demonstration -m "Remove file"
```

**Expected behavior**

I expect a commit that has `README.md` deleted.

**What happens instead**

The output looks normal:

```
INFO[0000] Running on 1 repositories
INFO[0000] Cloning and running script                    repo=klieret/multi-gitter-delete-bug-demonstration
INFO[0000] Pushing changes to remote                     repo=klieret/multi-gitter-delete-bug-demonstration
INFO[0001] Creating pull request                         repo=klieret/multi-gitter-delete-bug-demonstration
Repositories with a successful run:
  klieret/multi-gitter-delete-bug-demonstration #1
```

But you get a [PR with an empty commit](https://github.com/klieret/multi-gitter-delete-bug-demonstration/pull/1). Which is bad because the `README.md` should be deleted, but also bad because empty commits shouldn't be added by multi-gitter.
