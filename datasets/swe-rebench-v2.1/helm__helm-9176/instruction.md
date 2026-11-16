dependency name (and alias) clashes should be reported as errors
While trying to fix #9150 I found another class of issues with aliases and name clashes of dependencies.

I am proposing to report the following situation as errors on linting (and template/installing/upgrading) a chart:

```
dependencies:
- name: foo
  alias: baz # ← baz used twice
  version: 1.0.0
- name: bar
  alias: baz # ← baz used twice
  version: 1.0.0
```
```
dependencies:
- name: foo
  alias: bar # ← shadows chart below
  version: 1.0.0
- name: bar
  version: 1.0.0
```
```
dependencies:
- name: foo
  version: 1.0.0
- name: foo # ← chart with same name as above (although version or repo will be different, this will not work currently)
  version: 1.2.3
```
While the last example may be working in the future (see #7413), I can't see any valid use case for the first two examples.
Currently Helm renders templates, resulting in more or less undefined behaviour. Some templates will override each other, others won't, depending on file names in the actual charts and on the chart names itself.

Output of `helm version`:
`version.BuildInfo{Version:"v3.4.2", GitCommit:"23dd3af5e19a02d4f4baa5b2f242645a1a3af629", GitTreeState:"clean", GoVersion:"go1.14.13"}`

### Additional contract requirements

- `(*Metadata).Validate()` in package `pkg/chart` must reject a chart whose dependencies contain more than one dependency with the same name or alias. For a duplicated name or alias `foo`, it must return `ValidationError("more than one dependency with name or alias \"foo\"")`.
- A chart whose dependencies contain such a clash must be rejected when it is loaded
- Linting a chart whose dependencies contain such a clash must report the clash as an error.
- Template, install, and upgrade operations on a chart whose dependencies contain such a clash must report an error identifying the clash.
