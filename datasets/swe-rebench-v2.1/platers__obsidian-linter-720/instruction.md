Bug: `YAML Title Alias` does not escape commas
## Describe the Bug

If an h1 contains commas, the generated aliases array entry is not correctly escaped.
Obsidian expects an array for the aliases field; thus, any entry without quotes that contains commas is interpreted as multiple entries. Unfortunately, headers with commas are not enquoted, resulting in multiple aliases instead of one.

## How to Reproduce

The following example shows the problem:

``` markdown
---
aliases: [Consistent, Durable, and Safe Memory Management for Byte-addressable Non Volatile Main Memory]
---

# Consistent, Durable, and Safe Memory Management for Byte-addressable Non Volatile Main Memory

Lorem Ipsum...
```

Obsidian parses this as multiple aliases:
- Consistent
- Durable
- and Safe Memory Management for Byte-addressable Non Volatile Main Memory

This can be seen for example in the open document dialog.

<img width="732" alt="file-open-dialog" src="https://user-images.githubusercontent.com/20145354/218313805-a8154d7f-d602-4708-bcf9-348f36b24236.png">

## Expected Behavior

If a title contains commas, it should be enquoted, exactly like if it contains `:` and their like.

``` markdown
---
aliases: ["Consistent, Durable, and Safe Memory Management for Byte-addressable Non Volatile Main Memory"]
---

# Consistent, Durable, and Safe Memory Management for Byte-addressable Non Volatile Main Memory

Lorem Ipsum...
```

The alias is now correct:

<img width="724" alt="file-open-dialog-exp" src="https://user-images.githubusercontent.com/20145354/218314014-f99bfb21-33cd-45f8-8db8-8070fca5fafb.png">

## Device

- [x] Desktop
- [x] Mobile
