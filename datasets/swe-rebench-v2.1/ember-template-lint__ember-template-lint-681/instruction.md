Table group rule does not account for component composition
I have run into an issue with the table group rule. I am creating a contextual table component that will look something like this:
```hbs
<table>
  {{yield
    (hash
      Body=(component "table/body")
      Head=(component "table/head")
      Header=(component "table/header")
      Row=(component "table/row")
    )
  }}
</table>
```

Consuming contexts would do something like:
```hbs
<Table as |T|>
  <T.Head>
     ...
  </T.Head>
</Table>
```
As you can see, this is meant to be invoked in such away that the invoking context will employ a table group, but of course there is nothing forcing them to do so.

I could silence the lint error using a comment of course, but I almost think that any template that uses a `yield` as a first child of the `table` tag should not result in a lint error. Thoughts?
