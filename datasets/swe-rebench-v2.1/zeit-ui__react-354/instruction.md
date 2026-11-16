Make the modal accessible
<!-- Please do NOT DELETE the template. -->
<!-- No template issues will be closed. -->

# Feature request 🚀

  - [ ] I will create Pull Request
  - [x] It's just a suggestion

### Expected

  - Currently the modal component is not accessible, meaning if you use the keyboard to navigate (e.g. with `tab`) it will navigate the page in the background instead.
  - The modal component should capture keyboard focus and have proper aria attributes.

### Additional contract requirements

- When the modal is open, keyboard focus must be moved into the modal, and pressing `Tab` or `Shift+Tab` must keep focus within the modal (focus must not move to the page behind it).
  - The modal container element must expose the ARIA role `dialog` (i.e. `role="dialog"`).
- The modal container must have the CSS class `wrapper`.
