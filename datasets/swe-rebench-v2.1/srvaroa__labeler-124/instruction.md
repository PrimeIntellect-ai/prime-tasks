author-can-merge: false does not seem to work
Hiya,

As one of the criteria in a `labeler.yml` file, I have the following:
``` yml
 labels:
   - label: "Status: triage"
     draft: false
     author-can-merge: false
```

### I'd expect

The `Status: triage` label to be added to all non-draft PRs where the author doesn't have commit rights in the repo.

### What actually happened

The `Status: triage` label does not get added to PRs from outside contributors (who don't have commit rights to the repo).

### Other info

I haven't tested yet if it works when I set it as follows, but if it does, I'd still find that counter-intuitive, as I'd expect `author-can-merge: false` to be respected.

```yml
labels:
  - label: "Status: triage"
    negate: true
    draft: false
    author-can-merge: true
```

### Additional contract requirements

- The `author-can-merge` rule accepts a boolean value written as `true` or `false` (case-insensitive). It matches a pull request when the author's ability to merge equals the configured value, where an author whose association with the repository is `OWNER` can merge and any other association cannot.
- If the configured `author-can-merge` value is not a valid boolean, evaluating the rule produces an error.
