Support multiple userData stages by name
We should change the API while it's unreleased from
```yaml
userData:
  - stage: PreBootstrap
    [HIDDEN]
```

to
```yaml
  - name: my-stage
    stage: PreBootstrap
    [HIDDEN]
```
This will allow multiple scripts to be executed and better ordering

### Additional contract requirements

- The `userData` entry is a public configuration object with fields `name`, `stage`, and `data`; use `data` as the YAML key for the script content. For example:
  ```yaml
  userData:
    - name: my-stage
      stage: PreBootstrap
      data: |
        echo hello
  ```
- Add a public field `Name string` to the `UserDataStage` type in package `github.com/keikoproj/instance-manager/api/v1alpha1`.
- The public method `GetUserDataStages() ([]string, []string)` on `EksInstanceGroupContext` in package `github.com/keikoproj/instance-manager/controllers/provisioners/eks` returns the PreBootstrap scripts as its first result and the PostBootstrap scripts as its second result, each in the order the entries appear in the configuration.
- Entries whose stage is neither PreBootstrap nor PostBootstrap are ignored, and processing them produces a nonempty log message.
