Can't deploy project due to ...res.body.versions undefined
<!-- DO NOT DELETE
validate_template=true
template_path=.github/ISSUE_TEMPLATE/bug_report.md
-->

### [REQUIRED] Environment info

**firebase-tools:**
"13.0.2"

**Platform:**
Windows

### [REQUIRED] Test case

I just run `firebase deploy` on my project

### [REQUIRED] Steps to reproduce

- build a project
- deploy a project

### [REQUIRED] Expected behavior

the project is deployed

### [REQUIRED] Actual behavior

```
[debug] [2024-01-23T10:24:51.358Z] TypeError: res.body.versions is not iterable (cannot read property undefined)
    at Object.listVersions (C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\hosting\api.js:113:18)
    at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
    at async Promise.all (index 3)
    at async Object.gcTagsForServices (C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\hosting\runTags.js:14:31)
    at async Object.setRewriteTags (C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\hosting\runTags.js:77:9)
    at async convertConfig (C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\deploy\hosting\convertConfig.js:160:9)
    at async C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\deploy\hosting\release.js:21:21
    at async Promise.all (index 0)
    at async release (C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\deploy\hosting\release.js:14:5)
    at async chain (C:\Users\feder\Repository\anyx_mono_frontend\node_modules\firebase-tools\lib\deploy\index.js:38:9)
    ```

    so here

    ```
    async function listVersions(site) {
    [HIDDEN]
    [HIDDEN]
    [HIDDEN]
        [HIDDEN]
        [HIDDEN]
            [HIDDEN]
        }
        [HIDDEN]
            [HIDDEN]
        });
        [HIDDEN]
        [HIDDEN]
    [HIDDEN]
    [HIDDEN]
}
exports.listVersions = listVersions;
```


This issue appeared overnight.

### Additional contract requirements

- When a Hosting API response omits its collection field, `hostingApi.listVersions(site)` must return `[]` if `versions` is absent.
- A Hosting deployment must not fail solely because the Hosting API response omits the versions collection.
