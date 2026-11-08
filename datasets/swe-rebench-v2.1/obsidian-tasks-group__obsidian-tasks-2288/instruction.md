Make it easy to remove `.md` from `task.file.path`, `task.file.filename` and the query equivalents
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.
- [X] I am only requesting a single feature. Multiple changes should be split into individual requests, with links between them.
- [X] I believe my requested feature will be generally applicable to other users, not just me: it is not uniquely tied to my personal workflow.

### 🔖 Feature description

There have been a couple of cases of users wanting to use `query.file.filename` without the file extension `.md`:

---

- https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/2257#discussioncomment-7008068


> @FilSalustri If I understand your intention correctly, this is how you can now write your query using a pure Tasks filter, with needing to use Templater to embed some hard-coded test that won't update if the file gets renamed:
>
> ```
> filter by function task.description.includes('[[{{query.file.filename}}]]'.replace('.md', ''))
> ```

Then....

> One small problem with that `filter by function`:
>
> On my Mac, I can use a single quote as a legit filename character.
> So when `query.file.filename` gets expanded, it introduces an extra ' which throws an error - and rightly so.
>
> Is there a way to get `query.file.filename `to escape such characters?

---

- [On Discord](https://discord.com/channels/686053708261228577/965681451297304596/1155297547938697237)

> Oh okay, I guess it wasn't working because query.file.filename includes the  ".md" at the end, which doesn't work for me


### ✔️ Solution

I would like to provide:

- `query.file.pathWithoutExtension`
-  `query.file.filenameWithoutExtension`
- `task.file.pathWithoutExtension`
-  `task.file.filenameWithoutExtension`

### ❓ Alternatives

_No response_

### 📝 Additional Context

_No response_
