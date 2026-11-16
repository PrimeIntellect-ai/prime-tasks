performance: templ parse takes a long time and uses high CPU when unclosed void elements are used
**Describe the bug**
With the code I show here templ takes VERY long to compile, about 29 seconds. If I add more cases to the switch case it takes even longer, to the point where it is completey unusable and locked.

If I just remove the inputs in the top of the ActionStep template it goes below one second again...

This seems like a really funkey scanner issue to me, but I am sure you are much faster in finding the actual issue...

the templ process also climbs to ridiculous CPU usage while trying to generate in this case...

**To Reproduce**
Repo: https://github.com/s00500/templ-switchcaseissue

**Expected behavior**
Fast compile, no lockup

**Logs**
```
❯ templ generate
(!) templ version check: failed to read go.mod file: open /go.mod: no such file or directory
(✓) Complete [ updates=1 duration=28.554246583s ]
````

**`templ info` output**
```
❯ templ info
(✓) os [ goos=darwin goarch=arm64 ]
(✓) go [ location=/usr/local/go/bin/go version=go version go1.22.1 darwin/arm64 ]
(✓) gopls [ location=/Users/lb/go/bin/gopls version=golang.org/x/tools/gopls v0.16.1 ]
(✓) templ [ location=/Users/lb/go/bin/templ version=v0.2.759 ]

```
**Desktop (please complete the following information):**
macOS (latest, sonoma 14.6.1)

❯ templ version
v0.2.759

(Masterbuild from today)

![templ](https://github.com/user-attachments/assets/7bfc3c8e-be87-458b-a1a6-04b27b5210b1)
