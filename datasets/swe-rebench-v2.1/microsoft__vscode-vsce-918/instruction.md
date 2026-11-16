"INVALID URL" error for images with line break/irregular whitespace
Hi,

Thanks for your efforts working on this package.

I am getting an **"INVALID URL" error** when I run `vsce package`. I tracked down what is triggering the error to the following snippet in the _README.md_ of my extension:

```markdown
<p align="center">
<img src="img/screenshots/demo.webp" width="556" height="482"
alt="recording of  exploring view opened from the command 'Snippets Ranger: Show me that dur Range, Partner'. An entry of 'Markdown snippets' from the table of contents is selected and clicked, it takes the user down to the table with the snippets displayed for that extension."/>
</p>
```

It appears that the issue was cause by a line break/whitespace.

![Kazam_screenshot_00007](https://github.com/microsoft/vscode-vsce/assets/3703647/782ede8b-55d4-4bcf-974f-687587bc1651)

Here are 2 consecutive commits for [my extension](https://github.com/robole/vscode-snippets-ranger) with the substantive change to the _README_ that enable successful packaging:
- Unsuccessful packaging: https://github.com/robole/vscode-snippets-ranger/commit/3c9bde741698addc5a825309e60d4a8a109e3d70
- Successful packaging: https://github.com/robole/vscode-snippets-ranger/commit/cbc3d140eb73f92fc6d711de1aec0ad8db4d42d4

I am using VSCE version  2.1.5.

**It also might be worthwhile including the URL in the error for tracking down the issue more easily. It was a bit of a wild goose chase for me to fix this!!!**

### Additional contract requirements

- When parsing an image URL in a README fails during packaging, include the offending URL in the error message.
