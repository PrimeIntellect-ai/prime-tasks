[SelectionControlGroup] Comma-delimited list not working as expected
**Describe the bug**
In a SelectionControlGroup of type `checkbox`, when two values are checked, deselecting the second value results in `onChange` being called with `value1,` (with a comma) instead of `value1`.

**Expected behavior**
happen.
It shouldn't matter if I select a value at the back of the list.

If needd, I can provide a code sample later.

If this bug is confirmed, I can open a PR to fix it. If I'm not mistaken, it's just a wrong RegExp.
