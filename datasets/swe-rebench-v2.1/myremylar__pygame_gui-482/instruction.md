UIScrollingContainer sets dimensions instead of position
**Describe the bug**
In the version 0.6.8 that I am using, I spotted that in the `pygame_gui.elements.ui_scrolling_container` file, on line 147 in the `set_position` function, instead of updating the position, it updates the dimensions. (see screenshot below)

**Expected behaviour**
[HIDDEN]

**Screenshots**
<img width="598" alt="image" src="https://github.com/MyreMylar/pygame_gui/assets/74864888/b73ed331-b39d-42e0-8275-cadcd38907b0">

**Version:**
 - Pygame GUI version 0.6.8

### Additional contract requirements

- Calling `set_position(position)` on a scrolling container must move it to the requested position without changing its dimensions.
- When the scrolling container moves, its contained content must move with it, preserving the content’s position relative to the container.
