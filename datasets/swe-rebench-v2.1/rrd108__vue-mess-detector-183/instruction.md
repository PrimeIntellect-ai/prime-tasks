function size rule output wrong function name and length and does not show line number for the function
**Describe the bug**
When I run the analyzer on vue-mess-detector the output shows questions as the function name instead of createFiles, and shows no line number.

**To Reproduce**
run `yarn analyze src/generator/createRule.js -l=error`

1. What is the exact code you are analyzing?
`src/generator/createRule.js`

3. What is the output you are getting?
- rrd ~ function size
   File: src/generator/createRule.js
   Description: 👉 Functions must be shorter than 20 lines. See: https://vue-mess-detector.webmania.cc/rules/rrd/function-size.html
   Message: function (questions) is too long 🚨

**Expected behavior**
Message should be function (createFiles) in line 19 is too long

**Used version number of vue-mess-detector:**
0.38.0

### Additional contract requirements

- The reported function length is the number of lines of the function body only; the declaration line and the enclosing braces are not counted. For a block-bodied function this is the code between the opening and closing braces, and for a concise arrow function it is the expression after `=>`.
- The reported line number is the 1-based line of the function declaration within the analyzed script content, counting from the first non-empty line of that content.


- Each offense must have `rule` exactly equal to `${TEXT_INFO}rrd ~ function size${TEXT_RESET}` and `description` exactly equal to `👉 ${TEXT_WARN}Functions must be shorter than 20 lines.${TEXT_RESET} See: https://vue-mess-detector.webmania.cc/rules/rrd/function-size.html`.
