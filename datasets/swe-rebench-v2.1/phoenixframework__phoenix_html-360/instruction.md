Rendering array field as hidden inputs
I'm missing a way to automatically render an array field as hidden inputs. What I'd like to be able to do is this:

```elixir
<%= form_for :some_form, "/", [hidden: [some_field: ["one", "two", "three"]]], fn f -> %>
  <%= hidden_inputs_for f %>
<% end %>
```

Which should render to:

```html
<form action="/" method="post">
  <input type="hidden" id="something_0" name="something[]" value="one" />
  <input type="hidden" id="something_1" name="something[]" value="two" />
  <input type="hidden" id="something_2" name="something[]" value="three" />
</form>
```

Would it make sense to modify `hidden_inputs_for/1` to behave that way? If so, I can open a PR.

Background: I'm currently working on tighter integration between [flop](https://github.com/woylie/flop), [flop_phoenix](https://github.com/woylie/flop_phoenix) and `Phoenix.HTML.Form` by implementing `Phoenix.HTML.FormData` for a struct. The goal is to make setting up filter forms based on the library structs easier. To work well with the sortable table and pagination components, parameters like the page size etc. are added to the `:hidden` field in `form_for/2`, so that all of those parameters can be rendered with a single call to `hidden_inputs_for/1`. For sorting however, an `:order_by` field is used, which is a list. I tried modifying the protocol implementation to include that list as hidden fields as well, but I wasn't successful, which means at the moment I would have to add a modified `hidden_inputs_for/1` function to the my library. I'd rather have this part of Phoenix.HTML.
