Fix Request: Prevent sending expired tokens to Realtime channel
# Fix Request

To minimize the number of InvalidJWToken errors on the Realtime backend, we must check if the token is valid before pushing it.

Reference PR: https://github.com/supabase/realtime-js/pull/437

### Additional contract requirements

- When a token whose expiry (`exp` claim) lies in the past is set on the Realtime client, that token must not be sent to any subscribed Realtime channel.
- When a token that has not yet expired is set on the Realtime client, it must still be sent to subscribed Realtime channels.
