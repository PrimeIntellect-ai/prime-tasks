Add missing completion support for fish and PowerShell shells
### Feature request

CLI completion support for the Bash and ZSH shell is provided using the underlying [spf13/cobra](https://github.com/spf13/cobra/) library.  Cobra additionally supports fish and PowerShell completion support out of the box, see: [Generating shell completions](https://github.com/spf13/cobra/blob/main/site/content/completions/_index.md)

### Use case

Other than providing the same discoverability and convenience for fish and PowerShell users it will bring the  `kn` client in line with other plugins (e.g. quickstart) that have chosen to enable completion support for all 4 supported shells.

### Additional contract requirements

- When `kn completion` is invoked without an argument, its error message must contain `bash`, `fish`, `powershell`, `zsh`, `one`, and `argument`. When invoked with an unsupported shell, its error message must contain `bash`, `fish`, `powershell`, `zsh`, and `support`.
