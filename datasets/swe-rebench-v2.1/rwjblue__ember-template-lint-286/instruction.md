Changes for table-group rule.
Per [MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/table) the allowed contents of a `<table>` are:

> In this order:
> 1. an optional `<caption>` element,
> 2. zero or more `<colgroup>` elements,
> 3. an optional `<thead>` element,
> 4. either one of the following:
>   i) zero or more `<tbody>` elements
>   ii) one or more `<tr>` elements
> 5. an optional `<tfoot>` element

We are intentionally disallowing the option in 4 above (e.g. we require `<tr>` to be in `<tbody>`), but we still need to account for:

- [ ] `<caption>`
- [ ] `<colgroup`>
