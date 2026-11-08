content_tag/3 doesn't accept a string argument
I'm using the `tag` and `content_tag` functions to generate custom web component elements. Per the spec, custom elements must have dashed names like:

    <my-component></my-component>

The `tag/2` function currently allows a string argument

    iex> safe_to_string tag("my-component")
    "<my-component>"

However, the `content_tag/3` function does not:

    iex> safe_to_string content_tag("my-component", "content")
    ** (FunctionClauseError) no function clause matching in Phoenix.HTML.Tag.content_tag/2

Would it be possible to allow a string argument to the `content_tag` function?

Another alternative would be to require atoms, but replace underscores with dashes:

    iex> safe_to_string content_tag(:my_component, "content")
    "<my-component>content</my-component>"

That would match the behavior that currently exists for `data` attributes:

    iex> safe_to_string tag(:div, data: [my_attr: "foo"])
    <div data-my-attr="foo">

### Additional contract requirements

- `Phoenix.HTML.Tag.content_tag/2` and `Phoenix.HTML.Tag.content_tag/3` accept a string tag name in addition to an atom, rendering the named element with its escaped content and attributes.
