Gitlab issue references in commits can be rendered as merge-requests
## The problem

If a commit message such as:-

```
fix: Check if issue integration works (#3)
```

where `#3` links to an issue - as per https://docs.gitlab.com/ee/user/markdown.html#gitlab-specific-references - and shows as an issue link when viewed on gitlab.

This is rendered in the changelog (with added newlines) as:-

```markdown
* Check if issue integration works
  ([#3](https://gitlab.local/fred/project/-/merge_requests/3))
  ([`c3f8abd`](https://gitlab.local/fred/project/-/commit/c3f8abd9acaff597e6eae67c61e218556078b8cd))
```

Which links to `merge-request 3` - which would be `!3` as a gitlab link.

## Expected behavior

The changelog render should be:-

```markdown
* Check if issue integration works
  ([#3](https://gitlab.local/fred/project/-/issues/3))
  ([`c3f8abd`](https://gitlab.local/fred/project/-/commit/c3f8abd9acaff597e6eae67c61e218556078b8cd))
```

However I see that `#3` can be either a github (not gitlab) issue or PR.  Helpful!

## Additional context

The other Changelog enhancements that are in the queue might well fix this in passing...

The specific problem is in https://github.com/relekang/python-semantic-release/blob/2111d1e81d3f6210ad00289a788ede199a17ee33/semantic_release/changelog/changelog.py#L19-L23
