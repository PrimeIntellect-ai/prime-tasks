Cannot use a generic with a whatever variant
The following code does not compile [HIDDEN]:

```rust
use snafu::Snafu;

#[derive(Snafu)]
enum Error<T: std::fmt::Display> {
    #[snafu(display("X"))]
    X { thing: T },
    #[snafu(whatever, display("{message}"))]
    Custom {
        message: String,
        #[snafu(source(from(Box<dyn std::error::Error>, Some)))]
        source: Option<Box<dyn std::error::Error>>,
    },
}
```

Expanded:

```rust
or more information about this error, try `rustc --explain E0412`.

#![feature(prelude_import)]
#[prelude_import]
use std::prelude::rust_2021::*;
#[macro_use]
extern crate std;
use snafu::Snafu;
enum Error<T: std::fmt::Display> {
    #[snafu(display("X"))]
    X { thing: T },
    #[snafu(whatever, display("{message}"))]
    Custom {
        message: String,
        #[snafu(source(from(Box<dyn std::error::Error>, Some)))]
        source: Option<Box<dyn std::error::Error>>,
    },
}
///SNAFU context selector for the `Error::X` variant
struct XSnafu<__T0> {
    #[allow(missing_docs)]
    thing: __T0,
}
#[automatically_derived]
impl<__T0: ::core::fmt::Debug> ::core::fmt::Debug for XSnafu<__T0> {
    #[inline]
    fn fmt(&self, f: &mut ::core::fmt::Formatter) -> ::core::fmt::Result {
        ::core::fmt::Formatter::debug_struct_field1_finish(
            f,
            "XSnafu",
            "thing",
            &&self.thing,
        )
    }
}
#[automatically_derived]
impl<__T0: ::core::marker::Copy> ::core::marker::Copy for XSnafu<__T0> {}
#[automatically_derived]
impl<__T0: ::core::clone::Clone> ::core::clone::Clone for XSnafu<__T0> {
    #[inline]
    fn clone(&self) -> XSnafu<__T0> {
        XSnafu {
            thing: ::core::clone::Clone::clone(&self.thing),
        }
    }
}
impl<__T0> XSnafu<__T0> {
    ///Consume the selector and return the associated error
    #[must_use]
    #[track_caller]
    fn build<T: std::fmt::Display>(self) -> Error<T>
    where
        __T0: ::core::convert::Into<T>,
    {
        Error::X {
            thing: ::core::convert::Into::into(self.thing),
        }
    }
    ///Consume the selector and return a `Result` with the associated error
    #[track_caller]
    fn fail<T: std::fmt::Display, __T>(self) -> ::core::result::Result<__T, Error<T>>
    where
        __T0: ::core::convert::Into<T>,
    {
        ::core::result::Result::Err(self.build())
    }
}
impl<T: std::fmt::Display, __T0> ::snafu::IntoError<Error<T>> for XSnafu<__T0>
where
    Error<T>: ::snafu::Error + ::snafu::ErrorCompat,
    __T0: ::core::convert::Into<T>,
{
    type Source = ::snafu::NoneError;
    #[track_caller]
    fn into_error(self, error: Self::Source) -> Error<T> {
        Error::X {
            thing: ::core::convert::Into::into(self.thing),
        }
    }
}
[HIDDEN]
    [HIDDEN]
#[allow(single_use_lifetimes)]
impl<T: std::fmt::Display> ::core::fmt::Display for Error<T> {
    fn fmt(
        &self,
        __snafu_display_formatter: &mut ::core::fmt::Formatter,
    ) -> ::core::fmt::Result {
        #[allow(unused_variables)]
        match *self {
            Error::X { ref thing } => {
                __snafu_display_formatter.write_fmt(format_args!("X"))
            }
            Error::Custom { ref message, ref source } => {
                __snafu_display_formatter.write_fmt(format_args!("{0}", message))
            }
        }
    }
}
#[allow(single_use_lifetimes)]
impl<T: std::fmt::Display> ::snafu::Error for Error<T>
where
    Self: ::core::fmt::Debug + ::core::fmt::Display,
{
    fn description(&self) -> &str {
        match *self {
            Error::X { .. } => "Error :: X",
            Error::Custom { .. } => "Error :: Custom",
        }
    }
    fn cause(&self) -> ::core::option::Option<&dyn ::snafu::Error> {
        use ::snafu::AsErrorSource;
        match *self {
            Error::X { .. } => ::core::option::Option::None,
            Error::Custom { ref source, .. } => {
                source.as_ref().map(|e| e.as_error_source())
            }
        }
    }
    fn source(&self) -> ::core::option::Option<&(dyn ::snafu::Error + 'static)> {
        use ::snafu::AsErrorSource;
        match *self {
            Error::X { .. } => ::core::option::Option::None,
            Error::Custom { ref source, .. } => {
                source.as_ref().map(|e| e.as_error_source())
            }
        }
    }
}
#[allow(single_use_lifetimes)]
impl<T: std::fmt::Display> ::snafu::ErrorCompat for Error<T> {
    fn backtrace(&self) -> ::core::option::Option<&::snafu::Backtrace> {
        match *self {
            Error::X { .. } => ::core::option::Option::None,
            Error::Custom { .. } => ::core::option::Option::None,
        }
    }
}
```

### Additional contract requirements

- Deriving `Snafu` for a generic error type that contains a `whatever` variant must compile.
