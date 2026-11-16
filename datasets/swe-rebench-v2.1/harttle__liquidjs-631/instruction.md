Single or double quote breaks comments
Including a single or double quote (straight versions `'"`) inside a comment causes errors. Minimal examples:

```liquid
{% # that's %}
{% # "quoted" %}
```

Error:

```plain
tag "{% # that's %}\r\n" not closed, line:1, col:1
>> 1| {% # that's %}
      ^
   2|
TokenizationError: tag "{% # that's %}\r\n" not closed, line:1, col:1
```

Removing or replacing them with curly equivalents (`‘’“”`) fixes the error.

[Example from Shopify Liquid docs](https://shopify.dev/docs/api/liquid/tags/liquid) that also breaks due to apostrophe inside the comment:

> ```liquid
> {% liquid
>   # Show a message that's customized to the product type
>
>   assign product_type = product.type | downcase
>   assign message = ''
>
>   case product_type
>     when 'health'
>       assign message = 'This is a health potion!'
>     when 'love'
>       assign message = 'This is a love potion!'
>     else
>       assign message = 'This is a potion!'
>   endcase
>
>   echo message
> %}
> ```

### Additional contract requirements

- A straight single or double quote inside an inline comment must not cause the containing tag to be treated as unclosed.
- In a `{% liquid %}` block, an apostrophe in a comment line must not prevent subsequent Liquid statements from rendering.
