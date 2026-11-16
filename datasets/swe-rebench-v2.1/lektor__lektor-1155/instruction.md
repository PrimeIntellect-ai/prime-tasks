how can use databags as source for checkbox field
hi, i try to access databags from modeling file of a page, and below is the way i do:

[fields.label]
label = labels
type = checkboxes
source = site.databags.get_bag('categories')


and i got a error: TypeError: string indices must be integers

how can i use databags as a source of checkbox field?

thanks

### Additional contract requirements

- Data-bag lookups during Jinja rendering must resolve against the site supplied in the rendering context. If no site is supplied there, they must resolve against the active Lektor context.
- Values from a data bag must be usable as the options source for a checkbox field.
