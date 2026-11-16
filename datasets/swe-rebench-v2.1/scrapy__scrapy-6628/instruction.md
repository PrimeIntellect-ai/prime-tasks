GCSFeedStorage does not support feed_options
Since https://github.com/scrapy/scrapy/issues/6105, `feed_options` parameter needs to be supported by the feed storage classes.
Now with version 2.12.0, GCSFeedStorage does not have this parameter added, therefore it fails upon usage.
```
GCSFeedStorage.from_crawler() got an unexpected keyword argument 'feed_options'
```
