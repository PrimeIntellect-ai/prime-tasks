pipx list --json can print non-json to stdout
When nothing is installed, `pipx list --json` prints `nothing has been installed with pipx 😴` to stdout, and that's not valid json.

_Originally posted by @liskin in https://github.com/pipxproject/pipx/issues/660#issuecomment-828473735_

In addition, any warnings about the venvs are also printed to stdout, which is also non-valid json!
