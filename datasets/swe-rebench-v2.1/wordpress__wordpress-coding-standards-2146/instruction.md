Change WordPress.WP.EnqueuedResourceParameters.MissingVersion to warning
`EnqueuedResourceParameters` is [included](https://github.com/WordPress-Coding-Standards/WordPress-Coding-Standards/blob/206b30cd1051f36199f139bb11664bb1b75026e4/WordPress-Extra/ruleset.xml#L145) in `WordPress-Extra`.

It was recently added via #1378.

While I agree that it's a best practice to add a script version (WP will use its own version anyway if not given), I think we should reconsider this being reported as an _error_.

Example case, would be registering a script from a CDN e.g. `https://cdn.bootcss.com/backgrid.js/0.3.8/backgrid.min.js` - this already contains the version number, so having to add a version number as a separate argument doesn't make sense.

The arg is optional - if it was something that someone _must_ do (for which not doing would be an error), then it wouldn't be optional.

I realise this is for Extra, not Core, and that there are ways for individual projects to ignore, disable or change the type for this violation, but I'd like to see us re-consider changing it in WPCS.
