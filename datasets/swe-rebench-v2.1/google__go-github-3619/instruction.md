The Copilot Seat Billing API response for the assignee type can be "null"
There is a bug in the copilot seat details, per the spec null is a valid response type for the assignee:

```json
          "assignee": {
            "anyOf": [
              {
                "type": "null"
              },
```

https://docs.github.com/en/rest/copilot/copilot-user-management?apiVersion=2022-11-28#list-all-copilot-seat-assignments-for-an-organization

However, the code here errors with
Code:
https://github.com/google/go-github/blob/eff2bbd83e04dfdb38a9a878f7756e305656a9e2/github/copilot.go#L47

https://github.com/google/go-github/blob/eff2bbd83e04dfdb38a9a878f7756e305656a9e2/github/copilot.go#L212

 it's getting tested here and expecting an error, as invalid json.
This test checks for nil type, and returns an error, it should pass.
https://github.com/google/go-github/blob/eff2bbd83e04dfdb38a9a878f7756e305656a9e2/github/copilot_test.go#L30
