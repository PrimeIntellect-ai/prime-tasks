Dependencies need to be prefixed with environment name
According to docs and comments from maintainers, if I have project
```yaml
config/
- config.yaml
- my-env/
  - first.yaml
  - second.yaml
      template_path: templates/second.yaml
      dependencies:
        - first
- templates/
  - first.yaml
  - second.yaml
```

Then `first` should be deployed before `second`. However, this (`sceptre launch-env my-env`) does not work (no error message is seen - the stacks launch successfully, but are instantiated in parallel).
EDIT2: the following does work:
```yaml
config/
- config.yaml
- my-env/
  - first.yaml
  - second.yaml
      template_path: templates/second.yaml
      dependencies:
        - my-env/first
- templates/
  - first.yaml
  - second.yaml
```
.

Would be great if this could be fixed, or docs updated at the very least.

### Additional contract requirements

When launching an environment, a dependency written as a bare stack name must make that stack in the same environment finish deploying before the dependent stack begins deploying. A dependency written with the environment path (for example, `dev/first`) must likewise be honored as a prerequisite.
