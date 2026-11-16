Enable customizing CreatedAt and UpdatedAt touching
## Description

To enforce consistent timestamps between databases and service instances, we want to store all timestamps in UTC. However it is not possible to enforce UTC for `UpdatedAt` because pop will overwrite the value with `time.Now()` which includes the local time zone. In contrast, `CreatedAt` is only set to `time.Now()` when it is the zero value.

### Proposals

There are a view ways I can think of we can allow this kind of customization of time stamps.

1. Allow setting the `nowFunc`. This will enable globally defining the behavior.

1. Customizing model based. Add an interface a model can implement to `touchUpdatedAt` and `touchCreatedAt`, something like
  ```go
  type UpdatedAtSetter interface{
    TouchUpdatedAt()
  }
  ```

1. Both of above options.

I'm happy to implement this if you tell me the approach you like. I personally would prefer setting the `nowFunc` globally.

### Additional contract requirements

- Add a public function `SetNowFunc(f func() time.Time)` in the `pop` package (declared in `model.go`). It returns no value. It overrides the global time source used by pop when populating `CreatedAt` and `UpdatedAt`, so that after it is called, subsequent population of both `CreatedAt` and `UpdatedAt` uses the provided function.
