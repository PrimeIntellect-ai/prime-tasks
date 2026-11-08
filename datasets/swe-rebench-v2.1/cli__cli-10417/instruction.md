`gh project item-edit` should allow explicit `--number 0` field values
### Describe the bug

> Here's another case that I found out for `--number` that 0 is discarded as an invalid value:
>
> ```shell
> $ bin/gh project item-edit --project-id $projectId --id $itemId --field-id $fieldId --number 0
> error: no changes to make
> ```
>
> However, given above valid ranges, it is a valid value and can be set from UI:
>
> ![Image](https://github.com/user-attachments/assets/9b1591dc-82f8-4a5d-a3e5-2fb5f685a111)

 _Originally posted by @iamazeem in [#10342](https://github.com/cli/cli/issues/10342#issuecomment-2639592210)_

As stated in the issue, this appears to prevent users from accidentally setting item field values to zero due to zero value for float flags:

https://github.com/cli/cli/blob/756ba75c9ded6d1d201ddef4f271f4ba37057659/pkg/cmd/project/item-edit/item_edit.go#L79-L96

https://github.com/cli/cli/blob/756ba75c9ded6d1d201ddef4f271f4ba37057659/pkg/cmd/project/item-edit/item_edit.go#L148-L155

### Affected version

`2.66.1`

### Steps to reproduce the behavior

1. Create v2 project with `Number` fields
2. Add issue to project
3. `gh project item-edit --project-id $projectId --id $itemId --field-id $fieldId --number 0`

### Expected vs actual behavior

When a user calls `gh project item-edit` and `--number 0` is explicitly set, then we allow the item field value to be set to zero.

### Logs

```shell
$ GH_DEBUG=api ./bin/gh project item-edit --project-id PVT_kwDOBWmBn84Al2QA --id PVTI_lADOBWmBn84Al2QAzgXCZ4c --field-id PVTF_lADOBWmBn84Al2QAzgnpmgo --number 0
error: no changes to make
```
