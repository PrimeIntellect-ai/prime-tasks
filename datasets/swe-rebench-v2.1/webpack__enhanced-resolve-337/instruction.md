About the new change in AliasPlugin.js
last week, your team update the version of the enhanced-resolve
however, using v5.9.2, my project cannot build at all, it will be stuck while building.
It makes me really puzzled, because my project's alias is `'#': path.resolve(__dirname, './src'),`
when I change it into `'balabala': path.resolve(__dirname, './src'),`, it will continue to build. balabala can be anything but #
and when I change the [HIDDEN],  `'#': path.resolve(__dirname, './src'),` can also make it.
So I'm wondering the reason why your team make such a change

### Additional contract requirements

- A configured `#` alias must resolve successfully for both the exact request `#` and requests beneath it, such as `#/index`; resolution must not hang.
