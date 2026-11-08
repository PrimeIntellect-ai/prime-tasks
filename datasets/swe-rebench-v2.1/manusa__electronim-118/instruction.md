Do not detect some windows resize correctly on Linux
Resizing works when you drag the corner of the window: the content is correctly updated with the new resize. But when the resize is done by turning full screen a window, it is not detected.

### Additional contract requirements

- When a full-screen transition causes the window's content dimensions to settle after the resize notification is delivered, attached content views must ultimately fill the settled content area.
