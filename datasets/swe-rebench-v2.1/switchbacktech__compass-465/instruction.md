`META + d` does not duplicate event
### Where did this happen?

Production app, Local code with an up-to-date main branch

### Expected Behavior

Duplicated when focused on an event and typing `META + d`

This is the default "create bookmark" shortcut in Chrome. However, we can override it using event listeners and event functions so that it doesn't trigger.

[HIDDEN]

We should stick to `META` for consistency. This'll require us to prevent the default bookmark shortcut from trigger, like I shared in my example code

https://github.com/user-attachments/assets/3b2bb063-4405-4018-a2a4-5e97f91cc92b

### Current Behavior

`CTRL + d` duplicates an event


### Steps to Reproduce

1. Create an event (all-day or timed)
2. Click on it
3. Press `META + d`
4. Event should be duplicated, and the create bookmark event should not trigger
5. Repeat
6. Press `CTRL + d`
7. Nothing should happen

### Possible Solution

Change the handler and the conditional that checks for the key.

### Context

Bug was introduced in #418
