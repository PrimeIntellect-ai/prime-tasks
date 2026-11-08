bug: SearchBox - onSearch event is getting triggered on option selection using enter key
### Describe the bug
onSearch event is getting triggered when we select the option using the up-down arrow keys and press enter.

### To Reproduce
Provide step-by-step instructions to reproduce the bug:

1. Go to SearchBox, search for something and press enter
2. Select an option using the up-down arrow and press enter
3. This will trigger the onSearch event again.

### Expected behavior
When we select an option using an up-down arrow it should not trigger the onSearch event.

### Package versions
 - @medly-components/core : 6.26.2
