Ability to limit number of tasks by group
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.

### 🔖 Feature description

Currently the limit parameter limits the total number of tasks,
I'd like to be able to limit by number of tasks in a group, for instance to just show the very next satisfying task in a file.

### ✔️ Solution

The could have a syntax like:
```
group by filename limit 1
```
OR (as per @claremacrae's comment to make it easier to implement)
```
limit group 1
```

### ❓ Alternatives

_No response_

### 📝 Additional Context

_No response_

### Additional contract requirements

- The per-group limit instruction is spelled `limit groups <number>` (for example `limit groups 4`), or equivalently `limit groups to <number> tasks`.
