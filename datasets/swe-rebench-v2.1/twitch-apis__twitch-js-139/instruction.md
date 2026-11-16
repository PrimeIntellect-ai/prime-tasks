bug v2: whisper function is using /whisper instead of /w
## Expected behaviour

`client.chat.whisper(username, 'message')` should send whisper to `username` through /w command

## Actual behaviour

Unrecognized command: /whisper

## Steps to reproduce

Do a whisper throught whisper command

## Your environment

* Operating system(s):
* TwitchJS version: 2.0.0-beta.9
* NodeJS version: 10.7
* Browser(s):
