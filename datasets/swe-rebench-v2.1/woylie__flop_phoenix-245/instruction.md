Overriding `attrs` on `col` not working as advertised?
Hello! I just got started with Flop and I'm liking it so far.
I ran into an issue where the behaviour doesn't seem to agree with the documentation.

The [table slots docs](https://hexdocs.pm/flop_phoenix/Flop.Phoenix.html#table/1-slots) for `attrs` says:
>  Note that these attributes will override any conflicting `tbody_td_attrs` that are set at the table level.

I'm not finding that to be the case.

I have default table opts that includes:
```elixir
[
  tbody_td_attrs: [class: ["py-4", "pr-6"]]
]
```

Then, I have numeric columns that I want to align to the right, so I do:

```
<:col :let={{_id, transaction}} label="Amount" attrs={[class: ["py-4", "pr-6", "text-right"]]} field={:amount}>
```

The resulting HTML for each column then looks like:

```
<td class="py-4 pr-6">189.89 GBP</td>
```

I've tried lots of different combinations (strings, lists, maps), and the only thing that works is to remove the `tbody_td_attrs` from my defaults entirely, but then I'd have to set them manually for every column.

It looks like [the code that renders columns](https://github.com/woylie/flop_phoenix/blob/bf32828738a6e0a0579a82c45bdc98551c983db8/lib/flop_phoenix/table.ex#L192-L193) emits both the global/default options and any `attrs` provided to the slot. I can't find anywhere in the HEEx documentation that describes the expected behaviour when there are conflicts.

One other issue comes to mind then: getting the header to also align to the right. If `col_style` were changed to `col_attrs` for example, it would allow more flexible use of the `colgroup`. Then you could do something like:

```
<:col label="Amount" col_attrs={[class: "text-right", "text-monospaced"]} ...
```

Versions in use:
* flop_phoenix `0.22.1`
* phoenix `1.7.7`
* phoenix_live_view `0.19.5`
