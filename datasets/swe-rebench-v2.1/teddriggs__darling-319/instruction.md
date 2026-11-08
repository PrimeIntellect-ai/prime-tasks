Unknown fields are ignored in unit enum variants
The change in #260 allows non-existent fields to be added to an enum variant, and be silently ignored by `FromMeta::from_list`.

See the test I added in https://github.com/Sufflope/darling/blob/306_unknown_fields_are_ignored_in_unit_enum_variants/tests/unknown_fields.rs which passed up to `0.20.3` (adding parameters to the unit `Choice::Other` yields an error) and fails on the last example since `0.20.4` because the parameters are just ignored and I don't get an error.

The code is a bit convoluted because my use case is having options in an attribute macro, not a derive one, and I wanted to be able to write `#[my_macro(choices(one(params...), other))]`. I could not directly have a `Vec<Choice>` in `Opts`, it fails because `Vec<Choice>` doesn't implement `FromMeta` even though I derive `FromMeta` on `Choice`, that's why I added the `Choices` newtype.

Now it fails to emit an error on the last example because of this change in the `FromMeta` derived for `Choice`:

```diff
 impl ::darling::FromMeta for Choice {
     fn from_list(
         __outer: &[::darling::export::NestedMeta],
     ) -> ::darling::Result<Self> {
         match __outer.len() {
             0 => ::darling::export::Err(::darling::Error::too_few_items(1)),
             1 => {
                 if let ::darling::export::NestedMeta::Meta(ref __nested) = __outer[0]
                 {
                     match ::darling::util::path_to_string(__nested.path()).as_ref() {
                         "one" => {
                             ::darling::export::Ok(
                                 Choice::One(
                                     ::darling::FromMeta::from_meta(__nested)
                                         .map_err(|e| e.at("one"))?,
                                 ),
                             )
                         }
[HIDDEN]
                         __other => {
                             ::darling::export::Err(
                                 ::darling::Error::unknown_field_with_alts(
                                     __other,
                                     &["one", "other"],
                                 )
                                     .with_span(__nested),
                             )
                         }
```

Maybe I'm doing something completely wrong? I wrote this code initially on `darling` `0.14` and I'm trying to update to `0.20` actually.

### Additional contract requirements

- For `choices(other(foo = "bar"))`, the rendered error message must be exactly `Unexpected meta-item format `non-path` at choices`.
