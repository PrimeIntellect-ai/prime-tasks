Support Non-Semver Engine Versions in VSCE Validation and Comparison
The Regex used for checking valid engine version, can have values like 1.96.x, which is not a valid semver.
When using these kinds of version, the semver version comparison fails.

https://github.com/microsoft/vscode-vsce/blob/f1fc6d255d634849db9a7f28e59a031c49cd4918/src/validation.ts#L51-L53

https://github.com/microsoft/vscode-vsce/blob/f1fc6d255d634849db9a7f28e59a031c49cd4918/src/package.ts#L506
