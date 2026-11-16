Relative path with authority part present fails
Why relative paths forbidden when authority part is present?

https://github.com/guzzle/psr7/blob/69568e4293f4fa993f3b0e51c9723e1e17c41379/tests/UriTest.php#L599-L605

This violates [withPath](https://github.com/php-fig/http-message/blob/efd67d1dc14a7ef4fc4e518e7dee91c271d524e4/src/UriInterface.php#L242-L264) contract. Also there's [clear description](https://github.com/php-fig/http-message/blob/efd67d1dc14a7ef4fc4e518e7dee91c271d524e4/src/UriInterface.php#L312-L313) how to avoid problem described in the aforementioned code comment.
