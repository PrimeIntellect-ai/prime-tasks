Bug: Titles with special characters not getting escaped in aliases
## Describe the Bug

Titles containing the character `'` are not escaped when they are added to the list of aliases under the "yaml title alias plugin".

## How to Reproduce

Create a new vault with just this plugin installed. Enable the options:

 - escapes colons with space ....
 - yaml title aliases

Example to reproduce issue with:

``` markdown
# It's strange
```

or

``` markdown
---
aliases:
 - "It's strange"
---
# It's strange
```

## Expected Behavior

 - the title is escaped before being added to the list of aliases
 - if the escaped version of the title already exists in the aliases it does get added again

In both cases above the output should be

``` markdown
---
aliases:
 - "It's strange"
---
# It's strange
```

## Actual behaviour

``` markdown
# It's strange
```
becomes
```markdown
---
aliases:
  - It's strange
---
# It's strange
```
and
``` markdown
---
aliases:
 - "It's strange"
---
# It's strange
```
becomes
```markdown
---
aliases:
  - It's strange
  - "It's strange"
---
# It's strange
```

## Device

- [x] Desktop
- [ ] Mobile

### Additional contract requirements

- The YAML Title Alias rule's options accept an optional escape character named `defaultEscapeCharacter`. It defaults to `"` and determines the quote character used to wrap a title when the title is escaped before being added to the aliases list.
- The YAML Title rule's options accept an optional escape character named `defaultEscapeCharacter`. It defaults to `"` and determines the quote character used to wrap the title value when the title needs escaping.

- If an alias already represents the title after escaping, do not add that title a second time.
