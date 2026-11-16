Changes made in #257 introduces a BC break
Changes made in [#257](https://github.com/kbsali/php-redmine-api/pull/257/files#diff-a0d92f5dcb3b7fa15b6523c906ed0ad089ba350c1aa9d6cb36a011143fd246c8R66) introduces a BC break in the return value of [`AbstractApi::get()`](https://github.com/kbsali/php-redmine-api/pull/257/files#diff-a0d92f5dcb3b7fa15b6523c906ed0ad089ba350c1aa9d6cb36a011143fd246c8R47).
Prior to these changes, if the response body was empty, `get()` was returning `false`, and currently it returns `null`.
Since this package lacks a exception oriented flow in front of HTTP responses ending in error codes (400~599), my implementation relies in the return values to determine the situation about a request.

Obviously the compatibility with PSR-18 is great, I'd just like to expose this situation in order to verify if these changes could respect BC.
Note that this is the only one BC break I've checked, since this is the first issue I encountered after updating the dependency.
