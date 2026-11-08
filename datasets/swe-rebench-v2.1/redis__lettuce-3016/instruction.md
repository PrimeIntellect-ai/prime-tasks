Add support for creating regex- and subnet-based ReadFrom instances from a single string
## Feature Request

Spring Boot would like to be able to offer support for configuring Lettuce's `ReadFrom` setting using an application property. This is straightforward for the many `ReadFrom` constants that are supported by `ReadFrom#valueOf` but harder for the `regex` and `subnet` variants. We'd like to make this easier by enhancing `valueOf` to support `regex` and `subnet` as well.

#### Is your feature request related to a problem? Please describe

Please see https://github.com/spring-projects/spring-boot/pull/42588 for background and a description of the problem we're currently facing with trying to configure the `regex` and `subnet` variants with a single property.

#### Describe the solution you'd like

Our proposal is to enhance `valueOf` with support for a special syntax that allow the caller to indicate that a `regex` or `subnet` instance should be created and to provide the patterns or CIDR notations at the same time. The variant would be indicated by a prefix such as `regex:` or `subnet:` with the remainder of the string being the value. For example, `"regex:.*region-1.*"` or `"subnet:192.168.0.0/16"`. Comma-separated values could be supported as well such as `"subnet:192.168.0.0/16,2001:db8:abcd:0000::/52"`.

Supporting an order-sensitive `regex` hasn't really been considered yet. Perhaps an `order-sensitive-regex` would be the cleanest option?

#### Describe alternatives you've considered

We've considered defining this syntax in Spring Boot and pre-processing the value before calling `ReadFrom#pattern` or `ReadFrom#subnet` as appropriate. We concluded that it would be better for Lettuce itself to support the syntax as it broadens the benefit and also means that Spring Boot won't be an odd-on-out with a feature that may clash with a future change in Lettuce.

#### Teachability, Documentation, Adoption, Migration Strategy

Users will be able to call `ReadFrom#valueOf` and create any of the supported variants if they pass in an appropriately formatted string. No migration would be required as I would expect the existing `subnet` and `regex` methods to remain for those who prefer not to use a "magic" string.

### Additional contract requirements

- `ReadFrom.valueOf(String)` must accept a `subnet:` prefix followed by one or more comma-separated CIDR notations, for example `subnet:192.168.0.0/16` and `subnet:192.0.2.0/24,2001:db8:abcd:0000::/52`. The prefix is matched case-insensitively.
- `ReadFrom.valueOf(String)` must accept a `regex:` prefix followed by a regular expression, for example `regex:.*region-1.*`. The prefix is matched case-insensitively.
- When a recognized prefix is present but the value after it is empty (for example `subnet:`), `valueOf` throws an `IllegalArgumentException` whose message contains `Value must not be empty for the type '<type>'`, where `<type>` is the prefix exactly as written in the input.
- When the value after a `regex:` prefix is not a valid regular expression, `valueOf` throws an `IllegalArgumentException` whose message contains `is not a valid regular expression`.
- When the name is not recognized (for example `:192.0.2.0/24`), `valueOf` throws an `IllegalArgumentException` whose message contains `ReadFrom <name> not supported`, where `<name>` is the input string.
