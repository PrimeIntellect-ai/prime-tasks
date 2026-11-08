Bug: Single dollar sign in inline code replaced by wired content.
## Describe the Bug

If there is a single dollar sign in inline code format, linting appears to introducing wired content.
I ran into it when the `` `$` `` is replaced by a large amount of paragraphs of the original article.

I suppose it is a regex bug of internal linting rules.

## How to Reproduce

before:
``` markdown
# Title
- lorem `$` ipsum
```

after:
```markdown
# Title
- lorem `# Title
 ipsum
```
