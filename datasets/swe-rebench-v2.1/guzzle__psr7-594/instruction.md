StreamWrapper::stream_stat() should not always return an array
**PHP version**: >= 8.1

**Description**

`StreamWrapper::stream_stat()` is returning an array no matter what, this can cause problems when the inner stream has a size of `null`, because it's then transformed to `0`. The information "I don't know the size of this stream" is transformed to "this stream is empty".

Also, I'm wondering, why `url_stat()` (implemented in #156) does return a `mode` and  a `size` of `0` unconditionally.

**How to reproduce**

```php
$r = fopen('https://google.com', 'r');
assert(fstat($r) === false);

$stream = Utils::streamFor($r);
assert($stream->getSize() === null);

$r2 = StreamWrapper::getResource($stream);
assert(fstat($r2) === false); // This fails

$stream2 = Utils::streamFor($r2);
assert($stream2->getSize() === null); // This fails too (0 is returned)
```

**Possible Solution**

#594

**Additional context**

I'm trying to send a request with Guzzle, that request has a `null`-sized stream body wrapped in `StreamWrapper` as explained above (for some reasons that I cannot bypass), and Guzzle itself seems to rely on the fact that a `0`-sized body should not be sent in a request : https://github.com/guzzle/guzzle/blob/2779e868a00289e1b1fd854af030c43a06f4bcb4/src/Handler/CurlFactory.php#L251.

As a result, the request is sent without it's body.
