Set webpack target property to "node" in case it is missing in the config
<!--
1. Please check if an issue already exists so there are no duplicates
2. Fill out the whole template so we have a good overview on the issue
3. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
4. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Feature Proposal

## Description

It turned out in #274 , that, when the `target: "node"` property is missing in the webpack configuration, the compiles mostly work, but are missing the environment variables.
For the user this is not obvious, but can be checked by the plugin easily. It would be a great UX improvement, if the plugin could warn about the missing setting and set it to "node" automatically if absent.

Similar or dependent issue(s):
* #274

## Additional Data

* ***Serverless-Webpack Version you're using***:
* ***Webpack version you're using***:
* ***Serverless Framework Version you're using***:
* ***Operating System***:
* ***Stack Trace (if available)***:

### Additional contract requirements

- A warning is not required; the required behavior is to set the webpack target to `"node"` when it is missing.
