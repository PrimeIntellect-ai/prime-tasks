Bug: New "Format yaml array sections" toggle puts single Date value into array
## Describe the Bug

With the new "Format YAML Array" and "Format yaml array sections" rules, a single non-array date value in the YAML is getting converted into an array. I do not understand why!

## How to Reproduce

In "Settings" -> "Linter" turn on the first toggle under "Format YAML Array" and the "Format yaml array sections" toggle. Run the linter on the following:

``` markdown
---
date: 2022-08-14
tags: []
---

```

Result is:
``` markdown
---
date: [2022-08-14]
tags: []
---

```

This breaks all my dataview queries that use the `date` field, since they expect it to be a Date and not an array.

## Expected Behavior

No changes made by linter. Expected output:

``` markdown
---
date: 2022-08-14
tags: []
---

```

## Device

- [x] Desktop
