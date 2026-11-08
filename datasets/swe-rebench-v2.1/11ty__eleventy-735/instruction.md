front matter from subdirectories bleeds into its parent
**Describe the bug**
I see front matter data from an unrelated, nested file in other files.

I discovered that front matter overrides from data files overrides rather than merges so enabled `setDataDeepMerge(true)`. This led to odd behavior I'll show below:

**To Reproduce**
```
$ cat >_data/meta.json
{
  "image": "gimage",
  "description": "gdesc"
}
^D
$ cat >index.mustache
---
meta:
  description: topleveldesc
---

image: {{meta.image}}
desc: {{meta.description}}
^D
```

Now when I build, `_site/index.html` contains what I'd expect to see:
```
$ cat _site/index.html
image: gimage
desc: topleveldesc
```

Now add another file:
```
$ cat >something.mustache
---
meta:
  description: otherdesc
---

image: {{meta.image}}
desc: {{meta.description}}
^D
```

After I build, `_site/index.html` has changed:
```
$ cat _site/index.html
image: gimage
desc: otherdesc
```

This doesn't seem right.

**Expected behavior**
I did not expect front matter from one file to affect data in another file.

**Environment:**
 - OS and Version: Mac
 - Eleventy Version: 0.9.0
