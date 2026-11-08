Allow different notification message for dupe pets
I believe it should be easy enough to differentiate given the game message is different when receiving a duplicate pet?

### Additional contract requirements

- Pet notification templates must support `%GAME_MESSAGE%`; for a duplicate pet, it must render as `has a funny feeling like they would have been followed...`.
- - When the game message is `You feel something weird sneaking into your backpack.`, `%GAME_MESSAGE%` must render as `feels something weird sneaking into their backpack`.
- When the game message is `You have a funny feeling like you're being followed.`, `%GAME_MESSAGE%` must render as `has a funny feeling like they're being followed`.
