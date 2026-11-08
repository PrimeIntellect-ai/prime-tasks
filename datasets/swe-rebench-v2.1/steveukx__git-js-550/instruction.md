The first commit returns more than the ID in the CommitSummary.commit
This following behavior is an edge case only for a first (root) commit.

**Expected:**
`const co = await git.add(".").commit("first commit");`
should return the commitId in the CommitSummary.commit field.
```
CommitSummary {
  branch: 'master',
  commit: 'a78979d',
  summary: { changes: 2, insertions: 2, deletions: 0 },
  author: null
}
```

**Actual:**
```
CommitSummary {
  branch: 'master',
  commit: '(root-commit) a78979d',
  summary: { changes: 2, insertions: 2, deletions: 0 },
  author: null
}
```

The reason is the git output:
```
09:36 # git commit -m "hui"
[master (root-commit) 1153df9] hui
 1 file changed, 0 insertions(+), 0 deletions(-)
```

Feature or bug?
