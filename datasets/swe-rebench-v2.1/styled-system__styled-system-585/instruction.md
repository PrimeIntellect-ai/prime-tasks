Inheriting configs
Hey 👋

Im creating my own Style Function API on top of SS v5.

Without going too deep into why I'm doing this, I've created this minimal example to reproduce the issue: https://codesandbox.io/s/styled-system-issue-inheriting-configs-p3ibv

> Note: The example above is dumb, please don't fixate too much on it.

Basically, I'm importing the `border` function from SS and then creating my own `border` function based off its `config`.

Surprisingly the `borderRadius` prop stops working.

I've been knocking my head against the wall trying to figure out _why_ - but no luck (and now I have a headache)

Does this make sense to anyone?
