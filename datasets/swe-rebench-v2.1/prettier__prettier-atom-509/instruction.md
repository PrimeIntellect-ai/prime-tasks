Uncaught TypeError: Cannot read property 'version' of undefined
[Enter steps to reproduce:]

1. `cmd+shift+p`
2. `Prettier: debug`

**Atom**: 1.38.2 x64
**Electron**: 2.0.18
**OS**: Mac OS X 10.14.5
**Thrown From**: [prettier-atom](https://github.com/prettier/prettier-atom) package 0.57.0


### Stack Trace

Uncaught TypeError: Cannot read property 'version' of undefined

```
At /Users/psenders/.atom/packages/prettier-atom/dist/displayDebugInfo/index.js:27

TypeError: Cannot read property 'version' of undefined
    at getDebugInfo (/packages/prettier-atom/dist/displayDebugInfo/index.js:27:51)
    at HTMLElement.displayDebugInfo (/packages/prettier-atom/dist/displayDebugInfo/index.js:36:11)
    at CommandRegistry.handleCommandEvent (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:348418)
    at Object.didConfirmSelection (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:697714)
    at SelectListView.confirmSelection (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:871573)
    at HTMLDivElement.core:confirm (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:866452)
    at CommandRegistry.handleCommandEvent (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:348418)
    at KeymapManager.t.exports.KeymapManager.dispatchCommandEvent (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:1247210)
    at KeymapManager.t.exports.KeymapManager.handleKeyboardEvent (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:1243344)
    at WindowEventHandler.handleDocumentKeyEvent (/Applications/Atom.app/Contents/Resources/app/static/<embedded>:11:283624)
```

### Commands

```
     -0:28.4.0 snippets:next-tab-stop (input.hidden-input)
     -0:28.4.0 snippets:expand (input.hidden-input)
     -0:28.4.0 editor:indent (input.hidden-input)
  2x -0:27.3.0 core:backspace (input.hidden-input)
     -0:25.5.0 core:save (input.hidden-input)
     -0:21.5.0 editor:newline (input.hidden-input)
     -0:20.8.0 core:save (input.hidden-input)
     -0:12.1.0 command-palette:toggle (input.hidden-input)
     -0:11.1.0 core:move-down (input.hidden-input)
     -0:10.9.0 core:confirm (input.hidden-input)
     -0:10.9.0 prettier:format (input.hidden-input)
     -0:09.4.0 command-palette:toggle (input.hidden-input)
     -0:08.3.0 core:move-down (input.hidden-input)
     -0:08.0 core:move-up (input.hidden-input)
     -0:07.7.0 core:confirm (input.hidden-input)
     -0:07.7.0 prettier:debug (input.hidden-input)
```

### Non-Core Packages

```
goto-definition 1.3.4
linter 2.3.0
prettier-atom 0.57.0
```
