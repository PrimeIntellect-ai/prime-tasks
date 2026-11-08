Add default value support for annotate question
If an annotate question has a default value (a filename), the XForm should prepend this value with `jr://images/`.

So if the default column for question annotate question `a` contains `body.png`, the output in the XForm instance should be: `<a>jr://images/body.png</a>`.

Note that this value transformation is the same as what is used for values in the `media::image::` column.

(as agreed [here](https://forum.opendatakit.org/t/proposal-specify-a-fixed-image-to-be-annotated-or-signed/14954/18) - XForms spec PR [here](https://github.com/opendatakit/xforms-spec/pull/257)

### Additional contract requirements

- The "annotate question" in this request is an XLSForm `image` question. pyxform aliases the `image` type to `photo`, so the transformation applies to the `default` value of `image`/`photo` questions.
- A default value that already contains the prefix `jr://images/` is returned unchanged; it is not prefixed a second time.
- Defaults on questions that are not `image`/`photo` questions are left unchanged.
