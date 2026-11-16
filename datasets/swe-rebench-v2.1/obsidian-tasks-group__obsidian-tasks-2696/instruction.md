Blocking query doesn't recognize "no entry" emoji from Emoji Shortcodes plugin
### Please check that this issue hasn't been reported before.

- [X] I searched previous [Bug Reports](https://github.com/obsidian-tasks-group/obsidian-tasks/issues?q=is%3Aopen+is%3Aissue+label%3A%22type%3A+bug%22+sort%3Acomments-desc) didn't find any similar reports.

### Expected Behavior

When I add a  ⛔ character with the Emoji Shortcodes plugin (using the `:no_entry:` shortcode), it should indicate that this task is blocked.

### Current behaviour

The Tasks plugin reads that character as a part of the task. Editing the task shows it as part of the name. If you use the edit menu to add the block in, it adds a _different_ "No Entry" emoji. I had Ruby dump the bytes of both characters (in decimal):

- Emoji from Emoji Shortcodes: ⛔, [226, 155, 148]
- Emoji from Tasks: ⛔️, [226, 155, 148, 239, 184, 143]

I'm not an expert on encodings, so I'm not sure what the three extra bytes indicate. UTF-8 vs UTF-16?

To be perfectly frank, I'm not sure if this is an issue with Tasks or Emoji Shortcodes. But every other emoji I've tried with shortcodes lines up with what Tasks is expecting.


### Steps to reproduce

1. Install Tasks and Emoji Shortcodes plugins
2. Create a task with an ID
3. Create a task using the `:no_entry:` shortcode  and put the first tasks ID after it
4. Write a `is blocking` or `is blocked` query and tasks do not show up

### Which Operating Systems are you using?

- [ ] Android
- [ ] iPhone/iPad
- [ ] Linux
- [X] macOS
- [ ] Windows

### Obsidian Version

1.5.8

### Tasks Plugin Version

6.1.0

### Checks

- [ ] I have tried it with all other plugins disabled and the error still occurs

### Possible solution

[HIDDEN]
