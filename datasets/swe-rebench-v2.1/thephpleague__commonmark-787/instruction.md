Table extension: Add (optional?) container element to handle horizontal overflow
### Description

I'm using the Tables extension to add tables to markdown. On small screens the tables often extend outside of the viewport, breaking the page layout.

This is because elements with `display: table` do not respond to `width` and `max-width` the same way block elements do. There's no easy CSS way to constrain the table to its container. In the past I've handled it like so:

```html
<div style="overflow-x: auto; max-width: 100%">
  <table><!-- table innards... --> </table>
</div>
```

It would be nice if there was a way to configure the tables extension to wrap all tables in an element (`div`?) with a configurable class (e.g. `table-container`). This would make it easy to use the table extension without breaking responsive layouts.

In the meantime it seems like the only workaround is to extend the Table Renderer with a custom render function. (Which is not the end of the world, by any means, but it would be nice if this was a built-in option.)

I'm currently pretty busy at work, but if this is a feature you're open to I could try to find time to make a PR in the future.

### Example

Take the following markdown:

```md
|Heading|Heading|
|--------|--------|
|Content|Content|
```

It currently outputs something like this:

```html
<table><!-- table innards... --></table>
```

It would be nice if it output this instead:

```html
<div class="table-container">
  <table><!-- table innards... --></table>
</div>
```

To prevent making this a breaking change, it would probably be best to make this an optional configuration setting for the tables extension.

### Did this project help you today? Did it make you happy in any way?

This project is sooooooo good. I'm working on a project that requires some pretty complex custom markdown parsing, and the extension structure makes this really easy to set up. (I was originally planning to use a lot of regex, but I'm glad I found this project instead 😅 )

Thank you so much for your work on this project! It works great, is a breeze to build off of, and has saved me a ton of time!

### Additional contract requirements

The optional table-wrapping feature is configured through the `table` configuration
namespace. The exact configuration keys are:

- `table/wrap/enabled` (boolean, default `false`): when `true`, every rendered table is
  wrapped in a container element.
- `table/wrap/tag` (string, default `div`): the tag name of the container element.
- `table/wrap/attributes` (array, default `[]`): the attributes applied to the container
  element.

For example, the configuration

```php
['table' => ['wrap' => ['enabled' => true, 'attributes' => ['class' => 'table-responsive']]]]
```

must render a table as `<div class="table-responsive"><table>...</table></div>`.
