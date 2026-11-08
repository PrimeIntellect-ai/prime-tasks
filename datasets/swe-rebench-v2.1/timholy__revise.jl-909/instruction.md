Revise does not pick up path change for package extensions if I dev a package
If I dev a package in a running Julia session Revise picks up the path change for the main package but not for the extensions. And the stacktrace of a failure still points to the code in the compiled folder.

### Additional contract requirements

- After switching to the developed package, when an extension method throws, its stacktrace must include a frame whose file path starts with the developed package's path.
