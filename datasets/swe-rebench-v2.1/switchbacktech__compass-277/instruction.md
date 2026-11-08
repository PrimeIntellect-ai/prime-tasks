Creating someday events from command palette does not work
### Where did this happen?

Local code with an up-to-date main branch

### Expected Behavior

When selecting any of the event creation actions from the command palette, the respective draft is started:
- Create Week Event (W)
- Create Month Event (M)
- Create Event (C)

### Current Behavior

Nothing happens when selecting those Week/Month events (timed events work like normal)

### Steps to Reproduce

1. Launch command palette
2. Move mouse down to highlight the desired action
3. Press enter
4. Notice: nothing happens

### Possible Solution

Need to update how default someday events are created

### Context

Bug was introduced in #265

### Additional contract requirements

- `assembleDefaultEvent(category, startDate?, endDate?)` is exported from `packages/web/src/common/utils/event.util.ts`. It returns a default event for the given category. For `SOMEDAY_WEEK` and `SOMEDAY_MONTH`, the returned event includes `startDate` and `endDate` only when both are provided; when either is omitted, both `startDate` and `endDate` are empty strings.
