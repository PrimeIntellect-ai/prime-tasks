Uncaught TypeError: Cannot read property 'start' of undefined
[Enter steps to reproduce:]

1. Open Javascript file
2. Select text
3. Select "format with prettier" from context menu

**Atom**: 1.18.0 x64
**Electron**: 1.3.15
**OS**: Mac OS X 10.12.5
**Thrown From**: [prettier-atom](https://github.com/prettier/prettier-atom) package 0.36.1


### Stack Trace

Uncaught TypeError: Cannot read property 'start' of undefined

```
At /Users/jesse/.atom/packages/prettier-atom/dist/executePrettier/handleError.js:15

TypeError: Cannot read property 'start' of undefined
    at errorLine (/packages/prettier-atom/dist/executePrettier/handleError.js:15:19)
    at buildPointArrayFromPrettierErrorAndRange (/packages/prettier-atom/dist/executePrettier/handleError.js:24:22)
    at setErrorMessageInLinter (/packages/prettier-atom/dist/executePrettier/handleError.js:40:29)
    at /packages/prettier-atom/node_modules/lodash/lodash.min.js:49:114
    at executePrettierOnBufferRange (/packages/prettier-atom/dist/executePrettier/executePrettierOnBufferRange.js:45:5)
    at /packages/prettier-atom/dist/manualFormat/index.js:22:12
    at Array.forEach (native)
    at formatSelectedBufferRanges (/packages/prettier-atom/dist/manualFormat/index.js:21:43)
    at /packages/prettier-atom/node_modules/lodash/lodash.min.js:5:165)
    at /packages/prettier-atom/node_modules/lodash/lodash.min.js:97:162
    at /packages/prettier-atom/node_modules/lodash/lodash.min.js:5:165)
    at /packages/prettier-atom/node_modules/lodash/lodash.min.js:63:325
    at /packages/prettier-atom/node_modules/lodash/lodash.min.js:49:144
    at /packages/prettier-atom/dist/main.js:33:15)
    at CommandRegistry.module.exports.CommandRegistry.handleCommandEvent (/Applications/Atom.app/Contents/Resources/app/src/command-registry.js:265:35)
    at CommandRegistry.handleCommandEvent (/Applications/Atom.app/Contents/Resources/app/src/command-registry.js:3:65)
    at CommandRegistry.module.exports.CommandRegistry.dispatch (/Applications/Atom.app/Contents/Resources/app/src/command-registry.js:166:25)
    at AtomEnvironment.module.exports.AtomEnvironment.dispatchContextMenuCommand (/Applications/Atom.app/Contents/Resources/app/src/atom-environment.js:1320:34)
    at EventEmitter.outerCallback (/Applications/Atom.app/Contents/Resources/app/src/application-delegate.js:347:31)
    at emitThree (events.js:116:13)
    at EventEmitter.emit (events.js:194:7)
```

### Commands

```
     -2:43.4.0 core:select-all (input.hidden-input)
     -2:40.8.0 prettier:format (div.line)
     -0:47.3.0 core:confirm (input.hidden-input)
     -0:18.1.0 fuzzy-finder:toggle-file-finder (atom-workspace.workspace.scrollbars-visible-when-scrolling.theme-one-dark-syntax.theme-one-dark-ui)
     -0:16.9.0 core:confirm (input.hidden-input)
     -0:14.4.0 core:select-all (input.hidden-input)
     -0:10.5.0 prettier:format (span.syntax--comment.syntax--line.syntax--double-slash.syntax--js)
```

### Non-Core Packages

```
atom-beautify 0.30.3
atom-language-velocity 1.1.0
atom-terminal 0.8.0
build 0.68.0
build-gradle 0.6.0
build-npm-apm 0.12.0
busy 0.7.0
busy-signal 1.4.3
change-case 0.6.5
editorconfig 2.2.2
highlight-selected 0.13.1
intentions 1.1.2
language-gradle 0.0.3
language-groovy 0.7.0
linter 2.2.0
linter-eslint 8.2.1
linter-flow 5.6.0
linter-ui-default 1.6.2
minimap 4.28.2
prettier-atom 0.36.1
sort-lines 0.14.0
Sublime-Style-Column-Selection 1.7.4
terminal-plus 0.14.5
```
