Generic parameters with default values fail because they are placed before generated generic parameters in context selectors
I have a trouble using generic error type with default value, as in snafu-generated context selectors original generic parameters are placed before generated ones and if original generic parameter has default value it triggers compilation error, because defaults must be trailing. Error is very hard to understand as it points to original type where the generic parameter is the only, so is trailing, and you need to know how snafu works to understand what is true cause of that compilation error. I suppose the corresponding source is [https://github.com/shepmaster/snafu/blob/e09e9478bcc37968f711b0d5d22f04ea60963c77/snafu-derive/src/lib.rs#L774](https://github.com/shepmaster/snafu/blob/e09e9478bcc37968f711b0d5d22f04ea60963c77/snafu-derive/src/lib.rs#L774)

### Additional contract requirements

- An error type that derives `Snafu` must implement `std::error::Error` even when one or more of its generic parameters has a default value, including when such a parameter is omitted at the use site.
- For such an error, `std::error::Error::source` must return the source carried by the active variant, and no source for a variant that carries none.
- For such an error, `Display` must produce the message configured for the active variant.
- A wrapper error type that derives `Snafu` around another error must implement `std::error::Error` and delegate `source` and `Display` to the error it wraps.
