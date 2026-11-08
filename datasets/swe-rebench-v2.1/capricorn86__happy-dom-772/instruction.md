`blur` and `focus` events should not bubble through DOM
**Describe the bug**
When triggering `focus/blur` events on the element its ancestor nodes also receive `focus/blur` when they should not.

Per MDN docs `focus` and `blur` events don't bubble in DOM. But related `focusin` and `focusout` do bubble.
https://developer.mozilla.org/en-US/docs/Web/API/Element/focus_event
https://developer.mozilla.org/en-US/docs/Web/API/Element/blur_event

**Expected behavior**
`focus` or `blur` events should not bubble in DOM.

**Device:**
 - Version 8.7.1

Will open a PR soon with updated test cases.
