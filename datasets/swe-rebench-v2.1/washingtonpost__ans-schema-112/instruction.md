Add support for "Attached Redirects"
# Problem

There are cases where users want to store content in the Content API (or related systems) but want that content, when directly requested by url, to return another piece of content instead.  Information about where the content will redirect if navigated to directly is also useful.

# Proposal

Allow `related_content.redirect`, if present, to be a list of redirect objects instead of content or reference objects.  Content API will use redirect information from that redirect object in the fetch by canonical url endpoint.

# Example

```
{
  "_id": "ID_A",
  "type": "video",
  "version": "0.5.8",
  "canonical_url": "/path/to/some/video",
  "headlines": {
    "basic": "This video should only be shown embedded within an article."
  },
  "streams": [
    {
      "height": 360,
      "width": 640,
      "filesize": 5369656,
      "stream_type": "ts",
      "url": "https://videos.posttv.com/washpost-production/The_Washington_Post/20170223/58af2f07e4b0c9994378e6ff/58af3662e4b09a0a172ed097_t_1487877764511_mobile.m3u8",
      "bitrate": 300,
      "provider": "elastictranscoder"
    }
  ],
  "related_content": {
    "redirect": [
      {
        "type": "redirect",
        "version": "0.5.8",
        "canonical_url": "/path/to/some/video",
        "redirect_url": "/path/to/some/article"
      }
    ]
  }
}
```

### Additional contract requirements

- When present, `related_content.redirect` is an array containing at most one redirect object. A `related_content.redirect` array with more than one item does not validate against the 0.5.8 schema.
