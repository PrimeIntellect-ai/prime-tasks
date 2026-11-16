Move GitHub release headers up a level
The overall changelog format looks like

# Title of changelog

## 1.0.0

### Breaking changes

#### specific change note here

However, in a GitHub release, each release section is totally independent. The top-level single-hash header is the version number, which makes changes look, effectively, like this:

# 1.0.0

### Breaking changes

#### specific change note here

What a waste of header levels! We could make this a bit smarter by reducing the header level of every line included in the body, like:

# 1.0.0

## Breaking changes

### specific change note here

Which, conveniently, will make the rendered content of each change much nicer (as 4th-level headers look like plain ol' bold text.

### Additional contract requirements

The GitHub release body must retain its non-heading content, including prose, in its original order when heading levels are changed.
