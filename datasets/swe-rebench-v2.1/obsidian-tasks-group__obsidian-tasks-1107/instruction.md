tag searches do not honour # in query
### Expected Behavior

With this query:

`tags include #home`

I expect only tasks with `#home` to be matched.

So I expect this to be found:

`- [ ] stuff #home`

And this not to be found:

`- [ ] stuff #location/home`


### Current behaviour

`tags include #home`

matches both of this:

`- [ ] stuff #home`
`- [ ] stuff #location/home`


### Steps to reproduce

Create a markdown file called `delete me.md` with this content:

````text
# delete me

-  [ ] stuff I should be found #home
 - [ ] stuff I should not be found #location/home

```tasks
not done
tags include #home
path includes delete me.md
```
````

Expected behaviour: Only the first task is matched
Actual behaviour: Both tasks are matched

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

0.15.9

### Tasks Plugin Version

1.12.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

[HIDDEN]

Making this change does not break any of the many tests of tag searching.
