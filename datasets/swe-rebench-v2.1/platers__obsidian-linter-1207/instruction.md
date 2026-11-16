Bug: Remove Multiple Spaces removes indentation from nested bullet points INSIDE a nested callout
- [X] I have verified that I am on the latest version of the Linter

## Describe the Bug

A clear and concise description of what the bug is.

## How to Reproduce

``` markdown
> [!goal]+ Two goals of object-oriented design
>
> > [!def]- Cohesion
> > - How strongly related the parts are inside a class
> > - About a class
> > - A class is *cohesive* if the data and behaviour of these objects makes sense
> > - **High cohesion**:
> >     - A class does one job, and does it well
> > - **Low cohesion**:
> >     - Class has parts that do not relate to each other
> > - e.g., `Customer` class might have `getName`, `getAddress`, but also `sendEmail` that sends an email to the customer → Weird; not a major responsibility of the customer → ==not cohesive
```

## Expected Behavior

`> >     - A class does one job, and does it well` and `> >     - Class has parts that do not relate to each other` are expected to keep their spaces since it is a nested list inside a nested callout, but the remove multiple spaces setting removes the spaces between `>` and `-`.

## Device

- [X] Desktop
- [ ] Mobile
