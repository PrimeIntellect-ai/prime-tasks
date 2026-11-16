[Plugin Request] Vlive.tv
<!--
Thanks for requesting a plugin!
USE THE TEMPLATE. Otherwise your plugin request may be rejected.

First, see the contribution guidelines and plugin request requirements:
https://github.com/streamlink/streamlink/blob/master/CONTRIBUTING.md#contributing-to-streamlink

Plugin requests which fall into the categories we will not implement will be closed immediately.

Also check the list of open and closed plugin requests:
https://github.com/streamlink/streamlink/issues?q=is%3Aissue+label%3A%22plugin+request%22

Please see the text preview to avoid unnecessary formatting errors.
-->


## Plugin Request

<!-- Replace [ ] with [x] in order to check the box -->
- [x] This is a plugin request and I have read the contribution guidelines and plugin request requirements.


### Description
This is a live streaming site.
This site was originally mainly for idols who want to interact with fans, but now it has grown more, many people have registered and broadcast a number of more diverse programs.
<!-- Explain the plugin and site as clearly as you can. What is the site about? Who runs it? What content does it provide? What value does it bring to Streamlink? Etc. -->


### Example stream URLs

<!-- Example URLs for streams are required. Plugin requests which do not have example URLs will be closed. -->

1. https://www.vlive.tv/ (Home page)
2. https://www.vlive.tv/upcoming (Upcoming broadcasts will be show here)


### Additional comments, screenshots, etc.
This site has no live streaming 24/7 so you can visit the homepage and look down, sometimes seeing some people broadcasting there (IMG: https://i.imgur.com/rHBMmli.jpg).

Or visit this page to see upcoming shows: https://www.vlive.tv/upcoming

Hope you can support this page, thanks so much.

[Love Streamlink? Please consider supporting our collective. Thanks!](https://opencollective.com/streamlink/donate)

### Additional contract requirements

- A live broadcast on V LIVE is reached at `https://www.vlive.tv/video/<numeric id>`. Opening such a URL in Streamlink resolves to the V LIVE plugin, and it exposes the broadcast's available resolutions as playable streams (for example `720p`).
