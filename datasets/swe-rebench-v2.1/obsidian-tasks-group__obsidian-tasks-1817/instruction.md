Could the 5 Status Types be included in the CSS?
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.

### 🔖 Feature description

I'm trying to style loads of tasks and I have a variety of different custom statuses, so as far as I can tell, the only real information to tell me whether the task is done, todo, cancelled etc is the Task Status Type.

https://obsidian-tasks-group.github.io/obsidian-tasks/getting-started/statuses/status-types/#overview

- TODO
- IN_PROGRESS
- DONE
- CANCELLED
- NON_TASK

### ✔️ Solution

Could the status types be included as data attributes in the generated CSS?

### ❓ Alternatives

_No response_

### 📝 Additional Context

_No response_

### Additional contract requirements

Each rendered task list item must expose its status type (TODO, IN_PROGRESS, DONE, CANCELLED, or NON_TASK) through the CSS-usable `data-task-status-type` attribute.
