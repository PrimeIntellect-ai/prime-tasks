Introduce `disallowIn` as inverse of `allowIn`
It would be great if I could enforce some rules that only apply in some directories.

Currently, the only way to get that working is to construct a list of all options using wildcards, and then exclude the target from it. Not very ideal / scalable.

What do you think, would this be worth adding? Of course I can work on a PR to address it.
