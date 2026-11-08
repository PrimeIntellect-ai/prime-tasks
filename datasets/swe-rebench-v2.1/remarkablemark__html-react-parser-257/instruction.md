Throws error when styles are corrupted
<!--
Is this a bug report?

* Yes: Continue filling out the template.
-->

## Expected Behavior

<!-- What should happen. -->

- Parse a string with a corrupted style attribute, e.g. ‘&lt;p style="font - size: 1em"&gt;X&lt;/p&gt;’
- Return a version that skips the corrupted style ‘&lt;p&gt;X&lt;/p&gt;’?

## Actual Behavior

<!-- What happens instead. -->

## Steps to Reproduce

<!-- Describe a sequence of steps that anybody can repeat to see the issue. -->
Throws an exception: undefined:1:6: property missing ':'
## Reproducible Demo
https://jsfiddle.net/bjwmd5s6/
<!--
Creating a bug demo will help speed up the process of resolving the issue:

* CodeSandbox: https://codesandbox.io/s/940pov1l4w
* JSFiddle: https://jsfiddle.net/remarkablemark/7v86d800/
* Repl.it: https://repl.it/@remarkablemark/html-react-parser
-->

## Environment

- Version: 1.2.6
- Platform: Mac
- Browser: Tested on Firefox
