SetExpectedErrors allows only one error per status code
An endpoint may fail for different reasons with the same status code, e.g.:

<img width="511" alt="Screenshot 2022-04-14 at 18 27 30" src="https://user-images.githubusercontent.com/1078546/163442017-b82ed31e-1669-4abc-bcda-d087eae24756.png">
<img width="1654" alt="Screenshot 2022-04-14 at 18 27 52" src="https://user-images.githubusercontent.com/1078546/163442036-b9d6ef05-23a2-40d0-a346-73820793e48e.png">

It would be useful to be able to document multiple reasons an endpoint request can fail with the same status code. In my use case, the client can create a "prediction" via a JSON blob, and there are a million things that can be wrong with it, but most of them will be a BadRequest.

OpenAPI v3 supports this feature via `oneOf`: https://stackoverflow.com/questions/36576447/swagger-specify-two-responses-with-same-code-based-on-optional-parameter

As a separate easier question, the interface for `SetExpectedErrors` takes a list of errors, but there are implicit requirements for those errors to actually appear on the docs, e.g. a `.Status() int` function. Would you be able to clarify what exactly do I need to implement to make this work? Cheers.

### Additional contract requirements

- When `openapi.Collector.CombineErrors` is set to `"oneOf"`, the alternatives for each HTTP status must follow the order of the corresponding errors supplied to `SetExpectedErrors`, retaining repeated alternatives when multiple errors produce the same response schema.

- Every value passed to `SetExpectedErrors` must implement Go’s `error` interface. Its documented status and response schema come from the response value produced for that error: by default `rest.Err` uses `Status() status.Code` or `HTTPStatus() int` when provided (otherwise HTTP 500) and documents its `ErrResponse`; when a handler supplies `MakeErrResp`, that function’s returned status and response value determine the documentation.
