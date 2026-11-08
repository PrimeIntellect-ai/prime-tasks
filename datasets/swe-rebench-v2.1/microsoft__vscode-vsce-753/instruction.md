vsce publish error "Invalid URL"
Hi there, Thanks for your effort in this repository, today I found a problem when I published the extension.

### Reproduce
Insert GitHub theme flag of image URI. `#gh-light-mode-only`

<img width="1037" alt="image" src="https://user-images.githubusercontent.com/32405058/172049897-e93c5630-6f9c-42c5-a38b-3dd54eb722ec.png">

Then will be printed error info `Invalid URL`

<img width="753" alt="image" src="https://user-images.githubusercontent.com/32405058/172049965-f5b83630-bfb3-4a95-b94c-8e4cc7074314.png">

I debugged the code and found the error from [here](https://github.com/microsoft/vscode-vsce/blob/9ef1cf003317ca4160f1b69f2a40e5eeaa3ea4de/src/package.ts#L1527).
