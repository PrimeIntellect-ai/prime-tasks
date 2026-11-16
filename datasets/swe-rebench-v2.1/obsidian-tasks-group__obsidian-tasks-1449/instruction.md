regex support for recurring field
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.

### 🔖 Feature description

I would like to apply a regex to the recurring field.  For example, I have items which recur "every weekday" and would like to be exclude them in the filter.

### ✔️ Solution



(is | is not) recurring regex (matches| does not match) /some regex/

### ❓ Alternatives

recurring regex (matches | regex does not match) /some regex/

### 📝 Additional Context

_No response_

### Additional contract requirements

- Users can filter tasks by whether the task's recurrence rule matches a regular expression, using `recurrence regex matches /<regex>/` or `recurrence regex does not match /<regex>/` in a query. The first form selects recurrence rules matched by the expression; the second selects rules not matched by it.
