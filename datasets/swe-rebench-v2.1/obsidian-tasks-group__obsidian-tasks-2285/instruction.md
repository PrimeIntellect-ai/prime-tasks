'group by backlink' headings should link to the backlink location
### ⚠️ Please check that this feature request hasn't been suggested before.

- [X] I searched previous [Ideas in Discussions](https://github.com/obsidian-tasks-group/obsidian-tasks/discussions/categories/ideas-any-new-feature-requests-go-in-issues-please?discussions_q=category%3A%22Ideas%3A+Any+New+Feature+Requests+go+in+Issues+please%22+-label%3A%22status%3A+released%22+-label%3Aduplicate+sort%3Atop) didn't find any similar feature requests.
- [X] I searched previous [Issues](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+enhancement%22+sort%3Acomments-desc) didn't find any similar feature requests.

### 🔖 Feature description

Thank you for this great tool! My feature request is somewhat related to #473.

I find it very helpful to `group by backlink` and then, to avoid unnecessary duplicate information, `hide backlink`. However, the group header is not hyperlinked. So, the only way to see hover information is to keep showing backlinks *and* have that same information show as the group structure.

Ideally, the group could function as a single backlink, avoiding the repeated information across all tasks.

Thanks!

### ✔️ Solution

Ideally, I could see something like this:
<img width="335" alt="image" src="https://user-images.githubusercontent.com/23620506/219420066-20bcc076-0b29-4de4-a48d-95d93ce26738.png">


Where each group functions as a link instead of just the header and I get the best of both worlds.

This can be enabled by an option like `enable group links`, which tries to make a header into a link where possible.

### ❓ Alternatives

 A more robust solution would be to extend #473 and allow a header format of `[[{{task.backlink}}]]` (or whatever the formatting syntax is), but I have no idea how easy this is to implement or if it plays "nice" with other grouping options.

### 📝 Additional Context

_No response_

### Additional contract requirements

- Format backlink group headings as wikilinks: with no heading, use `[[c]]`; with a heading, use `[[c#heading|c > heading]]`. Keep both filename and heading when they are identical, as in `[[c#c|c > c]]`, and do not escape underscores, as in `[[_c_]]`.
