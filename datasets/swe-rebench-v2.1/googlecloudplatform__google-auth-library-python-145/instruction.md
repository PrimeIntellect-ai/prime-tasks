Add a five minute buffer to all expiration checks

### Additional contract requirements

- Expiration checks must continue to accept credentials and tokens until their expiration time is more than five minutes in the past.
- When `jwt.decode` rejects a token as expired, its `ValueError` message must contain `Token expired`.
