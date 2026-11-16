[Bug]: blurred text in zoom if use paintFirst: "stroke"
### CheckList

- [X] I agree to follow this project's Code of Conduct
- [X] I have read and followed the [Contributing Guide](https://github.com/fabricjs/fabric.js/blob/master/CONTRIBUTING.md)
- [X] I have read and followed the [Issue Tracker Guide](https://github.com/fabricjs/fabric.js/blob/master/CONTRIBUTING.md#%EF%B8%8F-issue-tracker)
- [X] I have searched and referenced existing issues and discussions
- [X] I am filing a **BUG** report.
- [X] I have managed to reproduce the bug **after** upgrading to the **latest** version
- [X] I have created an accurate and minimal reproduction

### Version

6.0.0-beta9

### In What environments are you experiencing the problem?

Chrome

### Node Version (if applicable)

None

### Link To Reproduction

https://codepen.io/jonnas123/pen/poqVQoG

### Steps To Reproduce


Hello, I'm new here, not sure if it's a bug or new feature request. Please go to the link and zoom the text. You will see the text is blurred. After I remove the paintFirst: "stroke" the blurred is gone. How to go with paintFirst: "stroke" without blurred? I need to use paintFirst: "stroke".



### Expected Behavior

After removing paintFirst: "stroke"

![sctwo](https://github.com/fabricjs/fabric.js/assets/90570681/52c1e563-7b46-403e-9611-2b2c58e5a590)



### Actual Behavior

Before removing paintFirst: "stroke"

![scone](https://github.com/fabricjs/fabric.js/assets/90570681/5efc6044-61f2-4d2a-9e75-a8b75b01e296)



### Error Message & Stack Trace

_No response_

### Additional contract requirements

Text that uses `paintFirst: "stroke"` should stay sharp as the canvas is zoomed.
