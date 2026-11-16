toApp() parameter need to have double quote when app name has two words
e.g "System Settings”

### Additional contract requirements

- For `toApp('Finder')` and `toApp('Xcode')`, the generated shell commands must be exactly `open -a "Finder".app` and `open -a "Xcode".app`, respectively.
- For each of `toApp('System Settings')`, `toApp('System Settings.app')`, `toApp('"System Settings"')`, and `toApp('"System Settings.app"')`, the generated shell command must be exactly `open -a "System Settings".app`.
