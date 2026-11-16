Transformer's transform method does not account for settings
# Steps required to reproduce the problem

1. Use a set of rules that include Analytics or Ads settings
2. Create instant article markup using the [Transformer::transform](https://github.com/facebook/facebook-instant-articles-sdk-php/blob/master/src/Facebook/InstantArticles/Transformer/Transformer.php#L285), instead of [Transformer::transformString](https://github.com/facebook/facebook-instant-articles-sdk-php/blob/master/src/Facebook/InstantArticles/Transformer/Transformer.php#L235)

# Expected Result
The markup includes the corresponding Analytics and/or Ads code

# Actual Result
The markup does not include the corresponding Analytics and/or Ads code [HIDDEN]


Note: To repro, replace `transformString` with `transform` in `SimpleTransformerTest::testSelfTransformerContent` and run the tests (`composer test`).
