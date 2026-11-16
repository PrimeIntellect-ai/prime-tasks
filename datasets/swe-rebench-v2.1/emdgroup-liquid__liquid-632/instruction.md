feat: Notification alert timeout
### Prerequisites

- [X] I know [how to contribute a proper feature request](https://github.com/emdgroup-liquid/liquid/blob/main/CONTRIBUTING.md#requesting-new-features).
- [X] I agree to follow the [Code of Conduct](https://github.com/emdgroup-liquid/liquid/blob/main/CODE_OF_CONDUCT.md).
- [X] I have searched for [existing feature requests](https://github.com/emdgroup-liquid/liquid/issues?q=is%3Aopen+is%3Aissue+label%3Afeature) that already request this feature, without success.

### Describe the feature request

It would be nice to have a possibility to set up timeout time for alert type notification also. For now we are able to set up timeout time only for "warn" and "info" type notifications.

### Describe the use case

We want all notifications in our system to disappear automatically after 6 seconds. For now we had to override the styles for "info" and "warn" notifications because we are able to set timeout only for them.

### Describe preferred solution

Would be nice if setting the timeout would work also for "alert" type notifications.

### Describe alternatives

None

### Related code

` new CustomEvent("ldNotificationAdd", {
      detail: {
        content: "Test notification",
        type: "alert",
        timeout: 4000,
      },
    })
`

### Additional information

_No response_
