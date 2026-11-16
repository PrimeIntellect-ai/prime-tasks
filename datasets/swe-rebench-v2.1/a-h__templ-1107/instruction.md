Generation gets stuck after update
After updating to [v0.3.850](https://github.com/a-h/templ/releases/tag/v0.3.850) `templ generate` would get stuck after generating a specific template. This happens both locally and in GitHub Actions. I've updated `go.mod` to the latest release as well.

Here's a sample verbose output:
```
$ ~/go/bin/templ generate -path ./templates -v
(✓) Walking directory [ path=/.../templates devMode=false ]
(✓) Starting event handler
(✓) Starting post-generation handler
(✓) Processing file [ file=/.../templates/A_templ.go ]
(✓) File not updated [ file=/.../templates/A_templ.go ]
...
(✓) Dev mode not enabled, process can finish early
...
(✓) Generated code [ file=/../templates/officetemplates/upsert_client.templ in=67.972917ms ]
(✓) File not updated [ file=/.../templates/officetemplates/upsert_client.templ ]
```

And generation would just get stuck here.

Reverting the executable and `go.mod` to [v0.3.833](https://github.com/a-h/templ/releases/tag/v0.3.833) fixes the issue for me:
```
$ git reset --hard HEAD~1 // resetting go.mod
$ rm ~/go/bin/templ
$ go install github.com/a-h/templ/cmd/templ@v0.3.833
$ ~/go/bin/templ generate -path ./templates -v
(✓) Starting event handler
(✓) Starting post-generation handler
...
(✓) Generated code [ file=/.../templates/officetemplates/upsert_client.templ in=60.899458ms ]
(✓) File not updated [ file=/.../templates/officetemplates/upsert_client.templ ]
(✓) Post-generation event channel closed, exiting
(✓) Waiting for push handler to complete
(✓) Waiting for event handler to complete
(✓) Waiting for post-generation handler to complete
(✓) Complete [ updates=0 duration=116.889459ms ]
```

Any way to debug what's going on?

EDIT: after looking at the logs again, it seems like it gets stuck after the very last file.

### Additional contract requirements

- `templ generate` must finish successfully and exit (it must not hang) for a `.templ` file whose `<script>` element contains a JavaScript template literal (a backtick string) that spans several lines, includes HTML markup, and has a `${...}` interpolation. For example:

  ```
  templ A() {
  <script>
  function showSuccessMessage(responseText) {
  const formResponse = document.getElementById('form-response');
  formResponse.innerHTML = `
  <div class="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">
  ${responseText}
  </div>`;
  }
  </script>
  }
  ```

- Markup-looking text inside a JavaScript string literal within a `<script>` element is treated as JavaScript text, so the file is generated without error.
