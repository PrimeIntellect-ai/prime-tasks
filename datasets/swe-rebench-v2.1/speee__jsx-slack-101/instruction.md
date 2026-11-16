<Escape> component will over-escape emoji shorthand
Now emoji shorthand such as `:+1:` is not included the escape target of `<Escape>` component. jsx-slack will render emoji even if wrapped in `<Escape>`.

Putting the discussion about whether escaping emoji shorthand aside, `<Escape>` component in the current specification is over-escaping emoji shorthand that has included underscore (`_`). Slack will render emoji consisted of a simple word such as `:cat:`, but emoji shorthand that has 2 and more words like `:arrow_down:` won't be rendered in `<Escape>` component because of over-escaped underscore.

If jsx-slack detected known emoji shorthand in `<Escape>` (with decision of keeping current specification), we have to disable underscore escaping only in emoji.
