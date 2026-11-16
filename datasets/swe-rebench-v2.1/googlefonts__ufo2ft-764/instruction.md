post table underlinePosition
The `postscriptUnderlinePosition` wasn't well specified in the UFO: it conflated the value for `CFF/Type1` and `post/CFF2`, where those values are actually different: `post/CFF2` value is the top of the underline, `CFF/Type1` is the middle of the underline.

The UFO spec got clarified to be clear that `postscriptUnerlinePosition` is `CFF/Type1' (https://github.com/unified-font-object/ufo-spec/issues/217).

The behavior for calculation from above is what the AFDKO has been doing, just need to update ufo2ft to follow suit.

I will PR a change (and tests) soon.

### Additional contract requirements

- `ufo2ft.constants` exports `OPENTYPE_POST_UNDERLINE_POSITION_KEY`, whose value is `public.openTypePostUnderlinePosition`.
- `public.openTypePostUnderlinePosition` holds the post/CFF2 underline position (the top of the underline). When it is present, the `post` table's underline position is that value.
- The CFF/Type1 underline position is `postscriptUnderlinePosition`. When `postscriptUnderlinePosition` is absent but `public.openTypePostUnderlinePosition` is present, the CFF/Type1 underline position is the public key value minus half of `postscriptUnderlineThickness`, rounded to an integer.
