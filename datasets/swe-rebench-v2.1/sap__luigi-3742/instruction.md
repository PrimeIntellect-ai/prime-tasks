Fix showConfirmationModal promise functionality
The following function is supposed to emulate the Core functionality with a Promise based structure. As in core, the developer should be able to have a callable callback function to send back the result which is then resolved.

Currently this callback is missing.

[HIDDEN]

https://github.com/SAP/luigi/blob/c95b4ce465006da125fa136096099dd59f3ae30f/container/src/services/webcomponents.service.ts#L101-L111

### Additional contract requirements

- The confirmation-modal request must expose a callable callback named `callback` to the event recipient. When invoked with result data, that callback must resolve the Promise returned by `showConfirmationModal` with that data.
