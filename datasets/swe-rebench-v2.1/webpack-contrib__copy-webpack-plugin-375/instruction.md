toType detection has broken "to: '[1]'"
* Operating System: MacOS
* Node Version: 10.15.3
* NPM Version: 6.9.0
* webpack Version: 4.29.6
* copy-webpack-plugin Version: 5.0.2

### Expected Behavior

You should be able to specify a to: like '[1]' or 'foo/[1]'.

### Actual Behavior

Files are being put in a literal directory named '[1]'.

### Code

I believe this is caused somewhere in this change: https://github.com/webpack-contrib/copy-webpack-plugin/commit/52f8be6809ae0b876225973d34ff65a3b6009192

I apologize for not submitting a PR instead, as that is my preferred way to deal with bugs, but I do not have time to dig on this right now.

### How Do We Reproduce?

Create a to: setting of '[1]' that is a replacement from a RegExp test.
