Missing function to update dependabot alerts
Reading [this file](https://github.com/google/go-github/blob/fd33b81221685302178ba197dbabe71326ca9051/github/dependabot_alerts.go
) there is no reference to a function to [Update a Dependabot Alerts](https://docs.github.com/en/rest/dependabot/alerts?apiVersion=2022-11-28#update-a-dependabot-alert
)

I would like to implement it but I am opening an issue first to ask if there is any other way to do it that I am currently missing.

### Additional contract requirements

- Add a public type `DependabotAlertState` in package `github` with fields `State string`, `DismissedReason *string`, and `DismissedComment *string`.
- Add a public method `UpdateAlert(ctx context.Context, owner, repo string, number int, stateInfo *DependabotAlertState) (*DependabotAlert, *Response, error)` on `DependabotService` in package `github`. It sends a PATCH request to `repos/{owner}/{repo}/dependabot/alerts/{number}` carrying the supplied state information, and returns the updated `DependabotAlert`, the raw `Response`, and an error.
- Add public methods `GetDismissedComment() string` and `GetDismissedReason() string` on `DependabotAlertState` in package `github`. Each returns the corresponding field value, or an empty string when the receiver or the field is nil.
