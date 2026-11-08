Authenticate chat messages
I didn’t have time to look at #871 before it was merged, but I see now it didn’t include authentication like we now have for all the other game master methods (partly because #853 was only merged after @TomasVidhall started work).

[HIDDEN] This would only allow players rather than spectators to chat, but currently an unauthenticated client could post a message claiming to be an authenticated player.

### Additional contract requirements

- When authentication is enabled for a match, a chat message is broadcast to connected clients only if the credentials supplied with it are valid for the player identified by the message's `sender`. A message that fails this check is not broadcast.
- A chat message without a player sender (from a spectator) cannot be accepted using a player's credentials, and neither can a message whose sender is a different player than the one the credentials belong to.
- Chat messages that pass authentication, and matches where authentication is not configured, continue to be broadcast to all connected clients.
- The client sends its player credentials along with each chat message through the supported transports (local and Socket.IO), so that the server can authenticate it.
- The server-side chat handler takes the match ID, the chat message, and the supplied credentials (a string or `undefined`) as its three arguments.
