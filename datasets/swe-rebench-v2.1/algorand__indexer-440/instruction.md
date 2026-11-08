Requesting an account at a round in the future should return an error.
## Summary
Currently it is silently ignored:
https://github.com/algorand/indexer/pull/373#discussion_r588331654

## Scope/Requirements
Check for error in `fetchAccounts`

## Urgency/Relative Priority
Low priority but would be nice to add in.

### Additional contract requirements

- When the requested round is greater than the current round, `fetchAccounts` must return an error whose message begins with the existing account-rewind error prefix, `errRewindingAccount`.
