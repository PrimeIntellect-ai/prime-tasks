Uncaught TypeError when clicking on "Download CSV" with no data in the table
<!--- Provide a general summary of the issue in the Title above -->
Clicking on "Download CSV" when the table is empty throws `TypeError`.

<!--
    Thank you very much for contributing to MUI-datatables by creating an issue! ❤️
-->

## Expected Behavior
<!---
    If you're describing a bug, tell us what should happen.
    If you're suggesting a change/improvement, tell us how it should work.
-->
If rows are empty, don't try to build the full CSV body.
The button is disabled, or download empty CSV.

## Current Behavior
<!---
    If describing a bug, tell us what happens instead of the expected behavior.
    If suggesting a change/improvement, explain the difference from current behavior.
-->
Errors are displayed in console and execution doesn't reach `onDownload` custom callback.
```javascript
utils.js?2b4c:51 Uncaught TypeError: data.reduce(...).trim is not a function
    at buildBody (utils.js?2b4c:51)
    at createCSVDownload (utils.js?2b4c:63)
    at TableToolbar._this.handleCSVDownload (TableToolbar.js?9399:125)
    at HTMLUnknownElement.callCallback (react-dom.development.js?cada:149)
    at Object.invokeGuardedCallbackDev (react-dom.development.js?cada:199)
    at invokeGuardedCallback (react-dom.development.js?cada:256)
    at invokeGuardedCallbackAndCatchFirstError (react-dom.development.js?cada:270)
    at executeDispatch (react-dom.development.js?cada:561)
    at executeDispatchesInOrder (react-dom.development.js?cada:583)
    at executeDispatchesAndRelease (react-dom.development.js?cada:680)
    at executeDispatchesAndReleaseTopLevel (react-dom.development.js?cada:688)
    at forEachAccumulated (react-dom.development.js?cada:662)
    at runEventsInBatch (react-dom.development.js?cada:816)
    at runExtractedEventsInBatch (react-dom.development.js?cada:824)
    at handleTopLevel (react-dom.development.js?cada:4820)
    at batchedUpdates$1 (react-dom.development.js?cada:18932)
    at batchedUpdates (react-dom.development.js?cada:2150)
    at dispatchEvent (react-dom.development.js?cada:4899)
    at interactiveUpdates$1 (react-dom.development.js?cada:18987)
    at interactiveUpdates (react-dom.development.js?cada:2169)
    at dispatchInteractiveEvent (react-dom.development.js?cada:4876)
buildBody @ utils.js?2b4c:51
createCSVDownload @ utils.js?2b4c:63
TableToolbar._this.handleCSVDownload @ TableToolbar.js?9399:125
callCallback @ react-dom.development.js?cada:149
invokeGuardedCallbackDev @ react-dom.development.js?cada:199
invokeGuardedCallback @ react-dom.development.js?cada:256
invokeGuardedCallbackAndCatchFirstError @ react-dom.development.js?cada:270
executeDispatch @ react-dom.development.js?cada:561
executeDispatchesInOrder @ react-dom.development.js?cada:583
executeDispatchesAndRelease @ react-dom.development.js?cada:680
executeDispatchesAndReleaseTopLevel @ react-dom.development.js?cada:688
forEachAccumulated @ react-dom.development.js?cada:662
runEventsInBatch @ react-dom.development.js?cada:816
runExtractedEventsInBatch @ react-dom.development.js?cada:824
handleTopLevel @ react-dom.development.js?cada:4820
batchedUpdates$1 @ react-dom.development.js?cada:18932
batchedUpdates @ react-dom.development.js?cada:2150
dispatchEvent @ react-dom.development.js?cada:4899
interactiveUpdates$1 @ react-dom.development.js?cada:18987
interactiveUpdates @ react-dom.development.js?cada:2169
dispatchInteractiveEvent @ react-dom.development.js?cada:4876
15:14:28.095 react-dom.development.js?cada:289 Uncaught TypeError: data.reduce(...).trim is not a function
    at buildBody (utils.js?2b4c:51)
    at createCSVDownload (utils.js?2b4c:63)
    at TableToolbar._this.handleCSVDownload (TableToolbar.js?9399:125)
    at HTMLUnknownElement.callCallback (react-dom.development.js?cada:149)
    at Object.invokeGuardedCallbackDev (react-dom.development.js?cada:199)
    at invokeGuardedCallback (react-dom.development.js?cada:256)
    at invokeGuardedCallbackAndCatchFirstError (react-dom.development.js?cada:270)
    at executeDispatch (react-dom.development.js?cada:561)
    at executeDispatchesInOrder (react-dom.development.js?cada:583)
    at executeDispatchesAndRelease (react-dom.development.js?cada:680)
    at executeDispatchesAndReleaseTopLevel (react-dom.development.js?cada:688)
    at forEachAccumulated (react-dom.development.js?cada:662)
    at runEventsInBatch (react-dom.development.js?cada:816)
    at runExtractedEventsInBatch (react-dom.development.js?cada:824)
    at handleTopLevel (react-dom.development.js?cada:4820)
    at batchedUpdates$1 (react-dom.development.js?cada:18932)
    at batchedUpdates (react-dom.development.js?cada:2150)
    at dispatchEvent (react-dom.development.js?cada:4899)
    at interactiveUpdates$1 (react-dom.development.js?cada:18987)
    at interactiveUpdates (react-dom.development.js?cada:2169)
    at dispatchInteractiveEvent (react-dom.development.js?cada:4876)
```
![image](https://user-images.githubusercontent.com/24522620/65883242-eea68200-e396-11e9-9437-482cb5e09889.png)

## Steps to Reproduce (for bugs)
<!---
    Provide a link to a live example (you can use codesandbox.io) and an unambiguous set of steps to reproduce this bug.
    Include code to reproduce, if relevant (which it most likely is).
-->
[codesandbox](https://codesandbox.io/s/muidatatables-download-empty-csv-jtctl)
1. Click on "Download CSV" Icon

## Your Environment
<!--- Include as many relevant details about the environment with which you experienced the bug. -->

| Tech         | Version |
|--------------|---------|
| Material-UI  |   4.3.1      |
| MUI-datatables  |     2.10.2    |
| React        |   16.8.6      |
