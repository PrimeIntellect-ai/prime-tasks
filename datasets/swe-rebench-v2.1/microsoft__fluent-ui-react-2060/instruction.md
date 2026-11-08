Keyboard navigation key handlers exception in RTL
## Bug Report
In RTL, text input (Input, TextArea) crashes with uncaught exception:

TypeError
keyCombinations.map is not a function

This causes bad rendering behavior.

### Steps
A clear and concise description of steps to reproduce the problem.
Use this example:
https://codesandbox.io/s/stardust-ui-example-p3n6j

See that text input both in RTL and LTR work normally.

Download Chrome V69
https://www.slimjet.com/chrome/google-chrome-old-version.php

See that when RTL is false, text input works normally. Then set it to true. See that any text input now causes an uncaught exception to be thrown.

### Expected Result
Text input to work normally.

### Actual Result
Uncaught exception causes crash.

### Version
Chrome: Version 69.0.3497.92 (Official Build) (64-bit)
Stardust: Stardust UI @ 0.40.1

### Testcase
[Fork, update, and replace this sandbox to show the bug]:
https://codesandbox.io/s/stardust-ui-example-8ismt
N/A
