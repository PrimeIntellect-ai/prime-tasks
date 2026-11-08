Cannot read property line of undefined
Error due to unexpected API from Errors coming from Prettier. From @mattapperson in https://github.com/prettier/prettier-atom/issues/226#issuecomment-313665570

> My stack trace...
> <details>
>
> TypeError: Cannot read property 'line' of undefined
>     at buildPointArrayFromPrettierErrorAndRange (/Users/mattapperson/.atom/packages/prettier-atom/dist/executePrettier/handleError.js:16:37)
>     at setErrorMessageInLinter (/Users/mattapperson/.atom/packages/prettier-atom/dist/executePrettier/handleError.js:32:29)
>     at /Users/mattapperson/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:49:114
>     at executePrettierOnBufferRange (/Users/mattapperson/.atom/packages/prettier-atom/dist/executePrettier/executePrettierOnBufferRange.js:45:5)
>     at callAppropriatePrettierExecutor (/Users/mattapperson/.atom/packages/prettier-atom/dist/formatOnSave/index.js:22:91)
>     at r (/Users/mattapperson/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:165)
>     at /Users/mattapperson/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:97:162
>     at r (/Users/mattapperson/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:5:165)
>     at /Users/mattapperson/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:63:325
>     at /Users/mattapperson/.atom/packages/prettier-atom/node_modules/lodash/lodash.min.js:49:144
>     at /Users/mattapperson/.atom/packages/prettier-atom/dist/formatOnSave/index.js:29:12
>     at attemptWithErrorNotification (/Users/mattapperson/.atom/packages/prettier-atom/dist/atomInterface/index.js:122:10)
>     at safeFormatOnSaveIfAppropriate (/Users/mattapperson/.atom/packages/prettier-atom/dist/formatOnSave/index.js:28:10)
>     at lazyFormatOnSave (/Users/mattapperson/.atom/packages/prettier-atom/dist/main.js:39:15)
>     at /Users/mattapperson/.atom/packages/prettier-atom/dist/main.js:120:14
>     at Function.module.exports.Emitter.simpleDispatch (/Applications/Atom.app/Contents/Resources/app/node_modules/event-kit/lib/emitter.js:25:20)
>     at Emitter.module.exports.Emitter.emit (/Applications/Atom.app/Contents/Resources/app/node_modules/event-kit/lib/emitter.js:141:34)
>     at TextBuffer.module.exports.TextBuffer.saveAs (/Applications/Atom.app/Contents/Resources/app/node_modules/text-buffer/lib/text-buffer.js:1119:26)
>     at TextBuffer.module.exports.TextBuffer.save (/Applications/Atom.app/Contents/Resources/app/node_modules/text-buffer/lib/text-buffer.js:1108:25)
>     at TextEditor.module.exports.TextEditor.save (/Applications/Atom.app/Contents/Resources/app/src/text-editor.js:925:32)
>     at Pane.module.exports.Pane.saveItem (/Applications/Atom.app/Contents/Resources/app/src/pane.js:780:24)
>     at Pane.saveItem (/Applications/Atom.app/Contents/Resources/app/src/pane.js:3:65)
>     at Pane.module.exports.Pane.saveActiveItem (/Applications/Atom.app/Contents/Resources/app/src/pane.js:763:25)
>     at Workspace.saveActivePaneItem (/Applications/Atom.app/Contents/Resources/app/src/workspace.js:1548:46)
>     at atom-workspace.core:save (/Applications/Atom.app/Contents/Resources/app/src/register-default-commands.js:236:38)
>     at CommandRegistry.module.exports.CommandRegistry.handleCommandEvent (/Applications/Atom.app/Contents/Resources/app/src/command-registry.js:265:35)
>     at /Applications/Atom.app/Contents/Resources/app/src/command-registry.js:3:65
>     at KeymapManager.module.exports.KeymapManager.dispatchCommandEvent (/Applications/Atom.app/Contents/Resources/app/node_modules/atom-keymap/lib/keymap-manager.js:610:22)
>     at KeymapManager.module.exports.KeymapManager.handleKeyboardEvent (/Applications/Atom.app/Contents/Resources/app/node_modules/atom-keymap/lib/keymap-manager.js:401:28)
>     at WindowEventHandler.module.exports.WindowEventHandler.handleDocumentKeyEvent (/Applications/Atom.app/Contents/Resources/app/src/window-event-handler.js:100:42)
>     at HTMLDocument.<anonymous> (/Applications/Atom.app/Contents/Resources/app/src/window-event-handler.js:3:65)
> </details>

### Additional contract requirements

- Add a public function `handleError({ bufferRange, editor, error })` in module `src/executePrettier/handleError.js`. It converts a Prettier syntax error into an Indie-Linter message and reports it by calling `linterInterface.setMessages(editor, messages)`.
- The error location may be provided either as `{ loc: { start: { line, column } } }` or as `{ loc: { line, column } }`; both shapes must be handled.
- The reported position must be adjusted by the provided `bufferRange`: the error line is offset by the range's start row, and when the error is on the first line the error column is offset by the range's start column.
- If the error object lacks the expected location information, `handleError` throws.
