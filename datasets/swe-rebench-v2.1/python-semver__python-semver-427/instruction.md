Replace method not compatible with SubClasses
<!-- Remove the comments below and adapt it to your needs  -->

# Situation
<!-- A clear and concise description of what the bug is. -->

Using the demonstration subclass from https://python-semver.readthedocs.io/en/latest/advanced/create-subclasses-from-version.html#creating-subclasses-from-version, the bump methods will create a new instance of the same SubClass.

When using the `replace` method, an instance of the `Version` class is created and not the subclass.

# To Reproduce
<!--
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error
-->

1. Create a subclass as shown in the document above.
2. `version = SemVerWithVPrefix.parse("v1.1.0")`
3. `dev_version = version.replace(prerelease="dev.0")`
4. Print `str(dev_version)`
5. This results in `1.1.0-dev.0` - dev_version is of type `Version` not `SemVerWithVPrefix`.

# Expected Behavior
<!-- A clear and concise description of what you expected to happen. -->

I expect `v1.1.0-dev.0` and `dev_version` to be an instance of SemVerWithVPrefix (or my class).

# Environment
- OS: [e.g. Linux, MacOS, Windows, ...] - Python 3.11 container - will be Debian.
- Python version [e.g. 3.6, 3.7, ...] - Python 3.11.5
- Version of semver library [e.g. 3.0.0] - semver==3.0.1

# Additional context
<!-- Add any other context about the problem here. -->

I suggest changing this the same way that the bump methods work:
[HIDDEN]
