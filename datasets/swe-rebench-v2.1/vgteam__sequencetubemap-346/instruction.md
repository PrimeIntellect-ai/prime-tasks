Use different default colors for different track types
In the solution for https://github.com/vgteam/sequenceTubeMap/issues/217 we found that, if you make a new track and then set its type, it keeps whatever default colors there are for a default created track. It doesn't magically adopt the default colors appropriate for the type of track you have made it be.

We should allow the default colors to differ depending on track type, and if you change track types it should reset the colors to sensible defaults for that track type.
