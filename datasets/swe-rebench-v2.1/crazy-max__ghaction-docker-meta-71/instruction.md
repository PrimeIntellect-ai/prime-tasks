Is there a variable for branch?
Is there a way to do the branch name dynamically as the prefix?

```
type=sha,prefix=${{ branch_name}}-,suffix=,enable=true
```

Something like that ^

### Additional contract requirements

- In `type=raw` tag values, expand `{{branch}}` to the branch name, `{{tag}}` to the tag name, and `{{sha}}` to the first seven characters of the commit SHA.
- The same `{{branch}}`, `{{tag}}` and `{{sha}}` expressions are also expanded in the `prefix` and `suffix` attributes of a tag, so that a branch name can be used dynamically as a prefix (for example `type=sha,prefix={{branch}}-`). When no branch name is available, `{{branch}}` may remain literal.
- When no tag name is available, `{{tag}}` expands to an empty string.
