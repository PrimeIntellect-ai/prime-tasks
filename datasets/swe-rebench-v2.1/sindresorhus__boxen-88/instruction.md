Allow border to be optional.
This tool has a lot of great features for creating boxes, and some of those features would be nice on their own. For instance, fullscreen would be great in some cases even without a border.

My use case, however, incorporates boxen into another utility. In order to achieve "no border", I have given boxen a "ghost border" which I strip after boxen's done working.

```js
borderStyle: {
	topLeft: ' ',
	topRight: ' ',
	bottomLeft: ' ',
	bottomRight: ' ',
	top: ' ',
	bottom: ' ',
	left: ' ',
	right: ' '
}
```

### Additional contract requirements

- A custom `borderStyle` object may set any of its sides (`topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `top`, `bottom`, `left`, `right`) to an empty string. An empty string draws nothing for that side. Callers can therefore obtain output without a visible border by giving every side an empty string: the output is the text itself, with no border characters.
- A borderless border (every side an empty string) can be combined with `fullscreen: true`. The text is still rendered, and no border characters are drawn.
