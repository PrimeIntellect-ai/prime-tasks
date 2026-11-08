Changing FormField seperator parameter to non-default breaks iteration over enclosing FieldList
I have a use case for generating a FieldList of a variable number of simple forms each enclosed in a FormField. I have attempted setting the separator parameter of the FormField. Changing FormField separator parameter to non-default (aka from "-" to "_" breaks iteration over enclosing FieldList. Only one entry is returned regardless of how many are in the list.

### Actual Behavior
Vastly simplified code below. Eveything works as intended if you leave separator set as default "-" but breaks if changed to "_"

```python
# Form for individual person's test score
class OneScoreForm(Form):
    Score = DecimalRangeField('Score',default = 1)

# List of forms for entering man people's test scores
class ScoringForm(Form):

    Scores = FieldList(FormField(OneScoreForm,  separator='_'), min_entries=1)
    submit = SubmitField('Submit Your Scores')

form = ScoringForm()

# Build Form
for person in people:
    form.Scores.append_entry()
    form.Scores[-1]['Person'].data = person.Person

# Render some HTML
# Get form data back with imputted scores

# Try to iterate over people and write to database
for score in form.Scores:
    # Put form data back into database
```
This returns only the first entry regardless of how many Score forms are appended to the list.


### Expected Behavior

Iterates over the whole list of submitted forms regardless of setting separator parameter.


### Additional Info

I do have a fix in my code that works by [HIDDEN] It does pass all the package tests but I still don't feel confident it will break something else.

The reason setting the separator matters to me is that I would like to eliminate the hyphens from he field names so I can use a bit of java on them to display the value of the range slider in real time. Hyphens are forbidden.

### Environment

* Python version: 3.8.5
* wtforms version: 2.3.3

### Additional contract requirements

- `FieldList` supports a `separator` argument, defaulting to `"-"`, that selects the delimiter between the list field’s name or ID and each entry index. A custom value, such as `"_"`, must be reflected in generated entry names and IDs and used to locate submitted entries.
- `FormField(separator=...)` selects the delimiter between an entry’s name or ID and the enclosed form’s child field names or IDs. The `FormField` and outer `FieldList` separators may differ; submitted fields must be parsed and all submitted entries made available for iteration using the respective separators.
