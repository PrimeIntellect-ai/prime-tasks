Bug: isSelf is false for membership commands
## Expected behavior

`isSelf === true` or `isSelf === undefined` for membership commands (cc @T1MOXA https://github.com/twitch-apis/twitch-js/issues/145#issuecomment-420771512).

## Actual behavior

`isSelf === false`

## Steps to reproduce

Issue a membership command and check the event's `isSelf` property.

## Your environment

* Operating system(s): n/a
* TwitchJS version: v2
* NodeJS version: n/a
* Browser(s): n/a

## Additional discussion

All memberships commands are _self_ commands, so is `isSelf` necessary for these events? Should it be set to `undefined` or should it be set to `true` to maintain consistency?
