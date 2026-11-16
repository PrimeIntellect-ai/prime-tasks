Bug: incorrect/spurious transformation être → êtree.
## Describe the Bug

When a text contains "être", this word is **transformed into "êtree"**, which is **incorrect** (in French).

## How to Reproduce

Steps to reproduce the behavior:

0. Make sure that "**Auto-correct common misspellings**" is On in the Linter settings.
1. Type "être" in a note.
2. Launch the linter.

## Expected Behavior

The word "être" should instead not be touched.

## Device

- [X] Desktop
- Mobile not tested
