Closing substack immediately causes crash
Opening and closing a substack without any content inside causes the program to crash with a "cannot read property 'length' of undefined" error.
Here are the exact steps to reproduce (you can't see the closing curly brace appear, as the program crashes as soon as i type it):

![katex_issue](https://user-images.githubusercontent.com/40633983/85164994-6d18bc00-b265-11ea-8184-512003ea541f.gif)


The last few items on the call stack are as follows:

![image](https://user-images.githubusercontent.com/40633983/85164319-7d7c6700-b264-11ea-8fc7-29227c7e216a.png)

I have set `throwOnError: false` so i would expect faulty input to cause red text, but not a crash.
This is in chromium, on Ubuntu 18.04, using your npm-package in a react-app.

### Additional contract requirements

An empty `\substack` (for example `\sum_{\substack{}} P(i,j)`) must be accepted and rendered successfully: it must build without throwing a parse error. This must hold both with the default settings and with `throwOnError: false`. It must not crash and must not be reported as faulty input.
