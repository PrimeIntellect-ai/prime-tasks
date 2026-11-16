(syntax sugar) Implement an `InOrder` func for mocks
<!-- If this is a question, consider using the discussion section of this repo -->
<!-- Here: https://github.com/stretchr/testify/discussions/new?category=q-a -->

## Description
<!-- A clear and concise description of what feature you are proposing -->
Since [gomock](https://github.com/golang/mock) has been archived, I am switching to testify's mock pkg.

One extremely neat feature that gomock had is the `InOrder` func:
https://pkg.go.dev/github.com/golang/mock/gomock#InOrder

Which allowed to very easily enforce expectation order by going from:
```go
someMock.EXPECT().ValidateArgs(gomock.Any(), 1).Return(nil),
someMock.EXPECT().ValidateArgs(gomock.Any(), 2).Return(nil)
```
to
```go
gomock.InOrder(
    someMock.EXPECT().ValidateArgs(gomock.Any(), 1).Return(nil),
    someMock.EXPECT().ValidateArgs(gomock.Any(), 2).Return(nil)
)
```

As opposed to the current API implemented in testify which is more cumbersome and less intuitive with the need to declare vars and pass them inside the last chained method.
https://github.com/stretchr/testify/issues/741
https://github.com/stretchr/testify/pull/1106

```go
call1 := mockThing.On("Init").Return(nil)
call2 := mockThing.On("Do").Return(nil).NotBefore(call1)
mockThing.On("Close").Return(nil).NotBefore(call1, call2)
```

Or I guess do some kind of nesting which reverse the chronological order of events and creates nesting.
```go
mockThing.On("Close").Return(nil).NotBefore(
    mockThing.On("Do").Return(nil).NotBefore(
        mockThing.On("Init").Return(nil).NotBefore(
            ... nesting
)
```

Ideally could be turned into:

```go
mock.InOrder(
    mockThing.On("Init").Return(nil),
    mockThing.On("Do").Return(nil),
    mockThing.On("Close").Return(nil)
)
```

## Proposed solution
<!-- Optionally a suggested implementation -->

I didn't looked into the codebase yet to know if that's easily feasible.
But my gut feeling says it could be trivial to [HIDDEN].
This issue is mostly to gather feedback.

## Use case
<!-- What is the motivation? What workarounds have you used? -->

More intuitive API.
