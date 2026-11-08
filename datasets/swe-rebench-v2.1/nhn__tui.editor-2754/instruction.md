Bold and Italic intersection incorrect Markdown
## Describe the bug
If you use bold and italic at the intersection of a word, then the output markdown will be incorrect

## To Reproduce
Steps to reproduce the behavior:
1. Go to "Wysiwyg" tab
2. Enter text "boldanditalic"
3. Make phrase "boldand" bold, then phrase "anditalic" italic
4. Go to "Markdown" tab.
5. Incorrect result is preview. Extra asterisks appeared.

![image](https://user-images.githubusercontent.com/8930952/134575623-3b97fe88-4753-4deb-93dd-244d00fb75bd.png)


## Expected behavior
Markdown will be `**bold*****and***&#8203;*italic*` or `**bold*****and***_italic_` and preview:
![image](https://user-images.githubusercontent.com/8930952/134576328-831ca41b-449f-491f-bd8b-e642e4f869f6.png)

Editor version: 3.1.0
