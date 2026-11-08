Bug: Headers starting with an alias break the YAML array
## Describe the Bug

A title starting with an aliased reference get's parsed in the YAML as "note: |...". The pipe is wrong and causes errors on save.

## How to Reproduce

Steps to reproduce the behavior:

1. Create new obsidian document
2. Give it an alias
3. Reference the alias at the start of the title
4. Hit save to create the YAML array
5. Notice that the YAML contains "note: |..."
6. Save again and get an error message
7. Check the console for the error details

Example to reproduce issue with:

``` markdown
---
note: |Broken Linter
aliases: Broken
---

# [[Broken Linter|Broken]] Linter
```

### Linter Log

```
Running linter
Running Format Tags in YAML
Running Escape YAML Special Characters
Running Format Yaml Array
Lint File Error in File 'ZZ_Other/Broken Linter.md':
Error "Format Yaml Array" encountered an error in the yaml:  a line break is expected (1:8)

 1 | note: |Broken Linter
------------^
 2 | created: 2023-01-27 12:51:35
 3 | modified: 2023-01-27 12:52:08
YAMLException: a line break is expected (1:8)

 1 | note: |Broken Linter
------------^
 2 | created: 2023-01-27 12:51:35
 3 | modified: 2023-01-27 12:52:08
    at ql (plugin:obsidian-linter:18:944)
    at P (plugin:obsidian-linter:18:978)
    at As (plugin:obsidian-linter:18:3294)
    at wp (plugin:obsidian-linter:19:4029)
    at qt (plugin:obsidian-linter:25:4899)
    at kp (plugin:obsidian-linter:25:2150)
    at qt (plugin:obsidian-linter:25:4870)
    at Op (plugin:obsidian-linter:25:7247)
    at _l (plugin:obsidian-linter:26:258)
    at Ep (plugin:obsidian-linter:26:469)
```

## Expected Behavior

Expected output if applicable:

"note:" doesn't start with a pipe.

``` markdown
---
note: Broken Linter
aliases: Broken
---

# [[Broken Linter|Broken]] Linter
```

## Screenshots

![image](https://user-images.githubusercontent.com/61841994/215080213-541da641-bb83-437b-8bbb-d6973a15f848.png)
![image](https://user-images.githubusercontent.com/61841994/215080261-25c7a9f2-8e62-441c-b6e5-21f0d4ce665d.png)

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

- It worked in the past. I have notes from earlier this month starting with an aliased reference. "note:" looks like this (it breaks when I save):
```
note: '[[Tittle|Alias]] more text [[Reference]]'
```
- Might have been introduced by #603, going by the title the PR changed header behaviour.
