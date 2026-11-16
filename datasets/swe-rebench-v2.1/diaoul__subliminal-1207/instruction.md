Subtitles fron NapiProjekt are not in .srt format
Hi,

So all subtitles downloaded from napiprojekt, are in mDVD format, not srt. I noticed though that Subliminal saves them with .srt extension, but if player supports only .srt, they will not work.

Is there a chance to use eg. subconv to convert such subtitles from mDVD to srt format on fly ?

Thanks
## <bountysource-plugin>

Want to back this issue? **[Post a bounty on it!](https://www.bountysource.com/issues/28560659-subtitles-fron-napiprojekt-are-not-in-srt-format?utm_campaign=plugin&utm_content=tracker%2F321252&utm_medium=issues&utm_source=github)** We accept bounties via [Bountysource](https://www.bountysource.com/?utm_campaign=plugin&utm_content=tracker%2F321252&utm_medium=issues&utm_source=github).
</bountysource-plugin>

### Additional contract requirements

The conversion must be applied by the subtitle saving workflow, not only when `Subtitle.convert` is called directly, so that a downloaded MicroDVD subtitle is written to disk as valid SRT.

`subliminal.core.save_subtitles(video, subtitles, *, subtitle_format=None, ...)` accepts an optional `subtitle_format` argument. When it is a non-empty string, each subtitle is converted to that format before it is written to disk. When a subtitle has no FPS of its own, the video's `frame_rate` is used for the conversion.
