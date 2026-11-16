Colorized output is not disabled when output is redirected
<!-- Thank you for filing a bug! Please feel free to answer as much or as little of this template as you can. -->

**Describe the bug**
Redirecting nox output does not correctly determine that stdout is not a tty and adds color control codes to the output.

**How to reproduce**
Given a noxfile that defines some targets, e.g. unit tests, run
`cd path/to/repo && python -m nox -s &> output-log.txt`

**Expected behavior**
The contents of `output-log.txt` should be plain ASCII (or UTF-8) and not contain cursor control codes.
