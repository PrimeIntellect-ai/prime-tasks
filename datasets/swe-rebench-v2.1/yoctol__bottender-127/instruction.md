CLI skip prompt for CI usage
Maybe `--skip-prompt` or `--no-prompt` ?

### Additional contract requirements

The Messenger attachment upload command must accept `--yes` to skip the interactive confirmation prompt, so uploads can be run noninteractively. Without this option, the existing confirmation flow remains in effect, and declining a forced upload exits without proceeding.
