Feature request: publish a theme
I think it would be nice to be able to publish a theme from themekit. It seems the only two ways are:

1. Shopify REST Admin Api -> online store -> theme -> PUT /admin/themes/#{theme_id}.json
2. Shopify Admin UI, on the version desired, click "publish".

My bet is that it was probably thought of but I don't know why it wouldn't be implemented.

### Additional contract requirements

- `publish(ctx)` returns the error returned by `ctx.Client.PublishTheme()` unchanged.
- When `ctx.Client.PublishTheme()` returns nil, `publish(ctx)` logs a success message to `ctx.Log` that contains the text `Successfully published theme` followed by the theme id from `ctx.Env.ThemeID`.
- `Client.PublishTheme()` returns an error whose message contains the API validation message when the API responds with validation errors.
