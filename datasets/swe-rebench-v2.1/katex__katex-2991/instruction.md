\widehat mathml toNode error
> Before reporting a bug
- [x] Check [common issues](https://katex.org/docs/issues.html).
- [x] Check the bug is reproducible in [the demo](https://katex.org). If not, check KaTeX is up-to-date and installed correctly.
- [x] Search for [existing issues](https://github.com/KaTeX/KaTeX/issues).

**Describe the bug:**
A clear and concise description of what the bug is. If your installation is available on the web or you can provide a minimal repo or CodePen that reproduces the bug, please add the link to it.

**To Reproduce:**
Steps to reproduce the behavior:
1. Open https://katex.org/
2. Input `\widetilde{ABCD}\tilde{ABCD}` in the demo-input textarea
3. Press F12 open Chrome DevTools
4. Switch to Elements tab and focus on the 'katex-mathml' element

**Expected behavior:**
The expected mathml should be:
```html
<math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><semantics><mrow><mover accent="true"><mi>x</mi><mo stretchy="true">^</mo></mover><mover accent="true"><mi>x</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\widehat{x}\hat{x}</annotation></semantics></math>
```

while, now it gets below:
```html
<math xmlns="http://www.w3.org/1998/Math/MathML" display="block"><semantics><mrow><mover accent="true"><mi>x</mi><mo stretchy="true">undefined</mo></mover><mover accent="true"><mi>x</mi><mo>^</mo></mover></mrow><annotation encoding="application/x-tex">\widehat{x}\hat{x}</annotation></semantics></math>
```

The **key** question is the `widehat` mathml render to an undefined textnode.

**Screenshots:**
![image](https://user-images.githubusercontent.com/1737782/117308963-94479e80-aeb4-11eb-96b5-a230669e5a16.png)

**Environment (please complete the following information):**
 - KaTeX Version: [0.13.6]
 - Device: [Desktop]
 - OS: [Mac OS Catalina 10.15.7]
 - Browser: [Chrome]
 - Version: [90]

**Additional context:**
None

### Additional contract requirements

When rendering MathML, `\widetilde{ABCD}` must use a tilde accent instead of rendering the text `undefined`. The expected `\widehat` MathML output must likewise use a stretchy caret accent instead of `undefined`.
