Unauthenticated client is allowed to connect at the moment when an authenticated client connects
Hi!

I've got a bug in 0.43.1. When I start an unautheticated client it can't connect, but if I start valid client in a different browser, the impostor client connects at that moment

### Additional contract requirements

- An unauthenticated client attempting to connect for a player must not be admitted as that player when a valid client connects.
- An unauthenticated client attempting to sync for the same player must receive no socket events in response, including when the sync attempts overlap.
- A client with valid credentials must still connect and receive its normal sync response.
