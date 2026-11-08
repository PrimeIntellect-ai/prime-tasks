Add `+` sign to supported list markers
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.
- [X] I am only requesting a single feature. Multiple changes should be split into individual requests, with links between them.
- [X] I believe my requested feature will be generally applicable to other users, not just me: it is not uniquely tied to my personal workflow.

### 🔖 Feature description

I think the `+` sign should be added to the supported markers for finding tasks. Currently only `*` and `-` are supported, but according to the [MD standard](https://daringfireball.net/projects/markdown/syntax#list) `+` is also a valid list character.

### ✔️ Solution

[HIDDEN]

### ❓ Alternatives

It would also be possible to have a user-defined list of markers defined in the properties of the plugin, but this solution would seem like additional work at the penalty of reduced performance due to the extra variable introduced.

### 📝 Additional Context

Since `+` is in a very convenient spot on a German keyboard, it seems like a good idea to add it to the RegEx. Therefore, I was wondering, why `+` wasn't available before. Maybe there are other implications I'm missing, so i didn't want to immediately create a pull request.

### Additional contract requirements

- A checklist line beginning with `+` must be recognized and parsed as a task, with `+` identified as its list marker.
