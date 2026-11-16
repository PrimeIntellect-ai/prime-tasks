Provide a way to disconnect animation TerminalInterceptor
I am working on a CLI with output similar to a docker pull, where I have several lines of status info that updates as operations progress. I am using a custom Animation subclass to handle rendering and updating this. Later, after this phase finishes, I want to continue printing other information, but leave the last state of the animation in place.

Currently, if I print new lines after the animations without first clearing them, the animations will re-print after the new lines.
What I would like to be able to do is to stop or disconnect the animation so that the last text it printed remains, and does not re-print or clear.

### Additional contract requirements

Call `Animation.stop()` to disconnect an animation without clearing its last rendered frame. After stopping, subsequent terminal output must not cause that animation to be cleared or rendered again.
