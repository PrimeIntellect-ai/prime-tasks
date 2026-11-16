Stream time information
Add an information in the player about time streamed.
such as `<Player>.streamTime`

### Additional contract requirements

The player exposes the elapsed streamed time as `player.state.playbackDuration`, in milliseconds. While playing, this value advances by 20 milliseconds for each audio or silence packet prepared for playback.
