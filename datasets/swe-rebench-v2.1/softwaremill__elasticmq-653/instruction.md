Invalid error response for ChangeMessageVisibility batch request
A `ChangeMessageVisibilityBatchRequest` that contains an entry with an invalid receipt handle fails entirely with status code 400 (`InvalidParameterValue; see the SQS docs`), rather than returning partial success containing a `BatchResultErrorEntry` with code `ReceiptHandleIsInvalid` for that particular entry.

`DeleteMessageBatchRequest` behaves as expected.
