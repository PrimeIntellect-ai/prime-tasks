Dialog auto-resize should be disabled
## Description

The dialog Electorn auto-resize feature should be disabled. Auto-resizing is handled internally by ElectronIM and should not be delegated to Electron's built-in behavior.

The following code:
https://github.com/manusa/electronim/blob/bcb5760d80dd00ec51055e1c404c02ff55eed874/src/browser-window/index.js#L20

[HIDDEN]

The test should be updated accordingly too:
https://github.com/manusa/electronim/blob/bcb5760d80dd00ec51055e1c404c02ff55eed874/src/browser-window/__tests/index.test.js#L39-L40

### Additional contract requirements

- Electron's built-in auto-resizing must be disabled for dialogs in all four dimensions: width, horizontal, height, and vertical.
