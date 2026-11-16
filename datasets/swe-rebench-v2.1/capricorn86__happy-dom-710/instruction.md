`composedPath` is incorrect for composed bubbling events originating from `HTMLAnchorElement`
**Describe the bug**
There's an issue where `Event.composedPath` will be constructed incorrectly if `event.target` is `HTMLAnchorElement` with `href` attribute being set.

**To Reproduce**
Steps to reproduce the behavior:
1. Create an <a> element with `href` attribute set to a valid domain, e.g. `https://example.com` and it attach to `body`.
2. Add event listener for created element, e.g. `click`.
3. Trigger `click` event on this element. Event should have both `bubbles` and `composed` set to `true`.
4. Inspect value of `event.composedPath()` inside `click` event handler.

**Expected behavior**
Composed path should be the following array: `[HTMLAnchorElement, document.body, document.documentElement, document, window]`.

**Additional context**
[HIDDEN]

https://github.com/capricorn86/happy-dom/blob/62085eba63a46c5e7716e52d50af82b6ee499fee/packages/happy-dom/src/event/Event.ts#L71-L78
