Bug:  inline LaTeX ends with Chinese may fail for 1 inserted space
## Describe the Bug
version 1.4.4, when Sapce between Chinese and English option is ON, linter will insert a space between ending Chinese and $, this may cause LaTeX fails to render properly.

## How to Reproduce

before: `$M0 = 现金$`,
after lint: `$M0 = 现金 $`, there is one redundant space added, and obsidian latex fails. (maybe this is the problem of obsidian, github can render it correctly.)

## Expected Behavior

expects that no space added before inline latex ending $ sign.
