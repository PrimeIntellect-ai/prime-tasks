Block absolute imports for local imports
### Background & motivation

Right now we allow absolute imports for specifying local imports (imports within a package). This is a legacy from the days before we had relative imports, and it’s causing some of the painpoints above.

We should instead ban absolute imports within a package, and force relative imports (either via a leading `.` or from the package root using `/` )


from: https://www.notion.so/kurtosistech/2023-09-Forked-Packages-Cleanup-d8bc4f5165ae4b039c07cdad56892459



### Desired behavior

This has three benefits:

- Users don’t have the option to get confused about which syntax they should use
- Eliminate the “accidentally pull from Github when I didn’t want to” issue
- Make it clearer at a glance which imports are imported from outside the package, and which imports are imported from inside


### How important is this to you?

Painful; the lack of this feature makes using Kurtosis frictionful.

### Additional contract requirements

- Reject an absolute locator that refers to a module within the current package.
- Accept a package-local locator beginning with `.` and a package-root locator beginning with `/`.
- Continue to accept absolute locators that refer to modules outside the current package.
