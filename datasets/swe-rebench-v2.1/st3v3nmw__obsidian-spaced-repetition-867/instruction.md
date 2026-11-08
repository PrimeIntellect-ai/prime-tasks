[BUG] Malformed card text during review, when multi-line card has space on Q/A separator line
**Describe the bug**
A multi line card get displayed without any text and screw up next card. When there is a leading space.

**To Reproduce**
Steps to reproduce the behavior:

1. Create a multi line card with a space in front of the separator
2. Go to review
3. See empty card/screw card

**Expected behavior**
Should Ignore leading space in the separator line.

**Screenshots**
![image](https://github.com/st3v3nmw/obsidian-spaced-repetition/assets/38220764/49226e85-ac2c-4e1d-9e7d-2ddc422c55bc)
![image](https://github.com/st3v3nmw/obsidian-spaced-repetition/assets/38220764/ad9b412c-7748-41c6-bd68-060f6d33ef29)
![image](https://github.com/st3v3nmw/obsidian-spaced-repetition/assets/38220764/43caebb3-2f29-4c95-a268-f99fa83e17af)

**Versions:**

-   OS: Win10
-   Obsidian version: v1.5.3
-   Plugin version: 1.11.0
-   Installer version: 5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) obsidian/1.4.16 Chrome/114.0.5735.289 Electron/25.8.1 Safari/537.36
