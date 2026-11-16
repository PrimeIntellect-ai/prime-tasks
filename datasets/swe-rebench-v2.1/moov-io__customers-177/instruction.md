Add endpoint for a single account
There are situations where you would want to request one account by ID, but the API currently only supports fetching a list of accounts for a customer.

Proposed endpoint: `/customers/:customerID/accounts/:accountID`

Why would this be useful?
- When creating an account, the response doesn't include the institution information, so either that should change OR there should be an efficient way to fetch that newly created account and not have to filter a list.
- In a UI reflecting transfer details, we need to look up the account, again it would be ideal to not have to filter a list.

### Additional contract requirements

- The endpoint is `GET /customers/{customerID}/accounts/{accountID}` and returns the single account identified by `accountID` for the given `customerID`.
- On success, respond with HTTP 200 and an `application/json` body containing the account.
- When the institution lookup for the account's routing number succeeds, the returned account includes the institution details.
- On failure (the account does not exist, the account lookup fails, or the institution lookup fails), respond with an error HTTP status and a JSON body containing an `error` field.
