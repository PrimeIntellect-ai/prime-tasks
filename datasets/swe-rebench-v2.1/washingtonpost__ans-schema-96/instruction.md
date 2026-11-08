Proposal: Comments Config
## Problem

Comments can be configured on a per-page basis, and some comment metadata is useful when rendering.

## Proposal

A `comments` object with the following properties (suggested by @StephanieDClark )

* `comments_period` - integer indicating how long (in days) until comments are closed
* `allow_comments` - boolean
* `display_comments` - boolean
* `moderation_required` - boolean

## Example

```
comments: {
  allow_comments: true,
  comments_period: 14,
  display_comments: true,
  moderation_required: false,
}
```

### Additional contract requirements

- When upverting a 0.5.7 story to 0.5.8, a `comments.favorite_comment` value must appear as `comments.additional_properties.favorite_comment`.
