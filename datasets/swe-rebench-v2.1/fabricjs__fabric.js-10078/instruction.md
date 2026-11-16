TOUCH and TOUCHMOVE related problems.
I have no touch device for debugging.
I m in the process of getting one or buying one.

I reference here all the issue to verify and fix.
Please add here the new issues related to touch.
allowTouchScrolling doesn't work
<!-- BUG TEMPLATE -->
## Version
3.4.0

## Test Case
https://codepen.io/den-bogdanov/pen/eYOwbPj

## Information about the environment
mobile browser chrome, safari

## Steps to reproduce
Open test case and try to scroll with help device emulation in devtools or from a mobile device

## Expected Behavior
Must be scrolling

## Actual Behavior
No touch scrolling

### Additional contract requirements

When `allowTouchScrolling` is enabled, a touch gesture over a canvas on a vertically scrollable page must allow native browser scrolling.
