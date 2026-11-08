staticcheck: ST1012 (problems with error variable names)
pkg/config/config.go:35:2: error var NoActiveConfigurationError should have name of the form ErrFoo (ST1012)
pkg/config/config.go:43:2: error var CannotDeleteActiveError should have name of the form ErrFoo (ST1012)
pkg/config/config.go:44:2: error var ReservedConfigNameError should have name of the form ErrFoo (ST1012)

### Additional contract requirements

The error variables in package `github.com/apigee/registry/pkg/config` must be renamed to names of the form `ErrFoo`:

- `ErrNoActiveConfiguration` is returned when no active configuration exists.
- `ErrCannotDeleteActive` is returned when attempting to delete the active configuration.
- `ErrReservedConfigName` is returned for operations that use the reserved configuration name `active_config`.
