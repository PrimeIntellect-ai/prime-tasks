HTML `readonly` attribute support
Currently wtforms does not handle the [HTML readonly attribute](https://developer.mozilla.org/en-US/docs/Web/HTML/Attributes/readonly). One can make a field read-only at rendering with the `render_kw` attribute.

On several projects I have been programmatically setting readonliness to fields, depending on the context, the user permissions etc. In the end I find myself writing the same tests and the same security guards again and again. Before processing the form I need to curate the readonly fields to protect against users sending modified values anyways. I also need to write the associated unit tests. This feels like boilerplate that could be avoided if wtforms would take care of this.

[HIDDEN] I did not have played with the code to verify my hypothesis though.

We could have a similar thing for the `disabled` attribute.

@davidism any thoughts?

Related discussions on SO:
https://stackoverflow.com/a/16576294/2180332
https://stackoverflow.com/a/9849156/2180332

Related ticket: #217

### Additional contract requirements

Two validators are provided in `wtforms.validators`: `readonly` and `disabled`. Each is called with no arguments and is added to a field's `validators` list.

- A field given `readonly` renders the HTML `readonly` attribute. Submitted data that changes its value is rejected, where the original value is the object data the field was created with, or its default when no object data is given. This applies to text, password, text area, integer, decimal and date fields.
- A field given `disabled` renders the HTML `disabled` attribute. Submitted values for it are rejected. This applies to text, integer and select fields.
