Path is undefined when using async functions within a custom function
**Describe the bug**
Path is undefined when using async functions within a custom function. This results in errors being shown on line 1 only.

**To Reproduce**

1. Given this API file
[my-sample-api.zip](https://github.com/stoplightio/spectral/files/9698432/my-sample-api.zip)

2. Run this CLI command `spectral lint -r .spectral.json reference/todo-api.yaml`
3. See errors are all on line 1
 <img width="568" alt="Screenshot 2022-10-03 at 7 41 29 PM" src="https://user-images.githubusercontent.com/17899454/193605594-58c5124d-83b4-487d-aca9-1520ae17740a.png">

**Expected behavior**
Correct line number should be shown with the error.
