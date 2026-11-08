Chore: Port missing `useRole` tests from React.
When #7 was closed it didn't have *all* the tests ported quite yet, this still needs to be done.

### Additional contract requirements

For the role cases covered here, the reference and floating elements must expose the corresponding ARIA roles and attributes, and reference attributes that depend on the open state must update with that state. Tooltip and label references identify the floating content through `aria-describedby` and `aria-labelledby`, respectively. A menu’s floating element must be labelled by its reference element. Select items must reflect whether they are selected through `aria-selected`.
