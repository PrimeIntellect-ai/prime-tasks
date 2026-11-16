Click prompts do not cooperate with readline module
When readline is imported and a user presses backspace during a Click prompt, the entire prompt message is erased and cursor goes to beginning of the line. This can be reproduced with the following code:

```
import click, readline
click.prompt("Input")
```

This is due to [Python issue 12833](https://bugs.python.org/issue12833). The official recommendation is that the prompt [HIDDEN]. I noticed that Click first displays the prompt message [HIDDEN] for the prompt. There is also a workaround by [HIDDEN], however, that may be ugly in the display.

### Additional contract requirements

- When `readline` is imported, pressing backspace during a Click prompt must not erase the prompt message or move the cursor to the beginning of the line.
