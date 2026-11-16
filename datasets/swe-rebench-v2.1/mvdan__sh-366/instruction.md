interp: Params isn't supported as an option to New
First of all, great project. We're tentatively planning to use it in an open project we'll be launching in two weeks (an automation tool with a twist) as syntax for our Makefile-like tasks. There are plenty of opportunities there as opposed to using bash directly, including better error messages and even debugging!

While integrating it with our tool, I noticed a problem with `Params`. While I was working on a fix, tests I added uncovered another issue.

PR: https://github.com/mvdan/sh/pull/364

I hope you'll find it not entirely worthless and can merge it, it's vital for us here, would hate to have to create a fork. :)
