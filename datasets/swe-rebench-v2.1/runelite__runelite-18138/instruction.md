Screenshot plugin deaths don't work on Doom deaths
### Type

Incorrect behavior

### Operating System

Windows

### OS Version

10

### Bug description

The Doom mechanic in colo kills you outright when you hit x amount of stacks (based on your modifier level), but is a death where you don't actually hit 0hp, so ActorDeath is never fired and screenshots aren't taken.

The chat message `You have been doomed!` is sent, and a custom death animation triggers when you die, (also varbit 9801 tracks doom stacks) so one of these might need to be used to handle said deaths.

Originally reported: https://github.com/pajlads/DinkPlugin/issues/472

### Screenshots or videos

_No response_

### RuneLite version

1.10.28.1

### Logs

_No response_

### Additional contract requirements

Doom-death screenshots must respect the existing setting that enables or disables player-death screenshots.
