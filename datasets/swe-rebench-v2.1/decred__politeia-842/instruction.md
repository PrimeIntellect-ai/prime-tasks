[www] Add new error status for invalid password
https://github.com/decred/politeiagui/issues/1069 requires a new ErrorStatusT for invalid passwords when User is changing its username. In summary, the current ErrorStatus does not distinguish between Invalid Password and Invalid Email.

### Additional contract requirements

- Add a public constant `ErrorStatusInvalidPassword` of type `ErrorStatusT` in package `politeiawww/api/www/v1`. It is returned when a username change is attempted with an invalid password.
