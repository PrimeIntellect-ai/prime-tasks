Regression in simple example, checkbox cannot be unchecked anymore
<!--

👋 Hey, thanks for taking an interest in 🏁 React Final Form!

-->

### Are you submitting a **bug report** or a **feature request**?

bug

<!-- For support request, please use Stack Overflow instead. This issue tracker is reserved for bugs and features. -->

### What is the current behavior?

Employed checkbox cannot be unchecked anymore

![image](https://user-images.githubusercontent.com/383212/34870142-87f55e1e-f789-11e7-8bac-ce33ebb0f8de.png)

<!-- If this is a bug, please include steps to reproduce and a minimal demo of the problem using Sandbox, Plunkr, WebpackBin or JSFiddle. -->

### What is the expected behavior?

to work :)

### Sandbox Link

simple example, https://codesandbox.io/s/ww40y2m595

<!-- Problems are much easier to understand and debug if they can be demonstrated in a minimal environment.  -->

### What's your environment?

<!-- Include 🏁 React Final Form version, 🏁 Final Form version, OS/browser affected, Node version, etc. -->

### Other information

<!-- Include here any detailed explanation, stacktraces, related issues, links for Stack Overflow, Twitter, etc. -->

### Additional contract requirements

- A boolean checkbox can be unchecked, and the corresponding form value becomes `false`.
- For checkbox options sharing one field, checking an option adds its value to the selected values; unchecking an option removes only that option and preserves the others.
