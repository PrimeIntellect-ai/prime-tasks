ENH: Exchange Code For Token to return Athelete summary
### Feature Type

- [ ] Adding new functionality to stravalib

- [X] Changing existing functionality in stravalib

- [ ] Removing existing functionality in stravalib


### Problem Description

When calling `client.exchange_code_for_token` the response does not include the athlete summary details
However the strava api does provide an athelete summary in the token swap
Without this we have to call get Athlete thus incurring additional requests to Strava, and reducing overall rate limits

### Feature Description

Add the Athlete dictionary in the `exchange_code_for_token` response

### Alternative Solutions

call get Athlete but this consumes an apps rate limits with the strava api

### Additional Context

_No response_

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional contract requirements

- `Client.exchange_code_for_token(client_id: int, client_secret: str, code: str, return_athlete: bool = False)` in module `stravalib.client` exchanges an OAuth authorization code for an access token.
  - When `return_athlete` is `False`, it returns an `AccessInfo` typed dictionary containing `access_token`, `refresh_token` and `expires_at`.
  - When `return_athlete` is `True`, it returns a tuple `(AccessInfo, SummaryAthlete | None)`: a `SummaryAthlete` instance when the token exchange response includes athlete data, or `None` when it does not.
  - The athlete information is taken from the token exchange response itself, without making a separate request to the athlete endpoint.
- `ApiV3.exchange_code_for_token(client_id: int, client_secret: str, code: str, return_athlete: bool = False)` in module `stravalib.protocol` returns a tuple `(AccessInfo, dict | None)`: the raw athlete dictionary from the token exchange response when `return_athlete` is `True`, or `None` when `return_athlete` is `False`.
- `SummaryAthlete` is importable from `stravalib.model`.
