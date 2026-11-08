useBlocker() doesn't pair well with redirects in beforeLoad
### Which project does this relate to?

Router

### Describe the bug

Using useBlocker() while navigating to a route that redirects makes the blocker trigger twice, please see the repro for an example.

### Your Example Website or App

https://stackblitz.com/edit/github-bel7g8?file=README.md

### Steps to Reproduce the Bug or Issue

Use useBlocker, and navigate to a route that redirects (in beforeLoad ?)

### Expected behavior

Just a single block.

### Screenshots or Videos

_No response_

### Platform

MacOS 14.6.1
Vite, ts-router etc all latest

### Additional context

_No response_
