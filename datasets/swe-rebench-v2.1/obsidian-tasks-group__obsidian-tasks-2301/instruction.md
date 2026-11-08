limit - enable opt in to show total numbers
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.
- [X] I am only requesting a single feature. Multiple changes should be split into individual requests, with links between them.
- [X] I believe my requested feature will be generally applicable to other users, not just me: it is not uniquely tied to my personal workflow.

### 🔖 Feature description

you should add a display to limit that allow to view the total task when limit crops it

when i do something like

```
``tasks
not done
due before today
limit 5
``
```

and for example i have 22 overdue tasks - the display show `5 tasks`

### ✔️ Solution

instead of just seeing the number of tasks,

i'd like to see `5/22 tasks`

### ❓ Alternatives

instead of doing this by default ,

the display could also jut indicate `First 5 tasks (total unknown)`

and then a opt in like `limit 5 with stats` could enable the more expensive full counting

### 📝 Additional Context

...

### Additional contract requirements

- When a limit crops the results, display the shown count before the original count, separated by "of"; the task noun after the original count reflects that original count, for example `5 of 22 tasks`.
- For cropped results, separate the shown and original counts with "of". A task noun may follow the shown count; if present, it is "task" when the shown count is 1 and "tasks" otherwise. A task noun follows the original count and is "task" when the original count is 1 and "tasks" otherwise. Thus `1 of 2 tasks` and `1 task of 2 tasks` are both valid when one of two tasks is shown, while a cropped result with one original task reads `0 of 1 task`.
