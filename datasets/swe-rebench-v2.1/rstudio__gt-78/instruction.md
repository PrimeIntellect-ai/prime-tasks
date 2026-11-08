Fix the `inline_html_styles()` utility function
The `inline_html_styles()` function is used for inlining CSS styles in a gt table and this is an essential preparatory step for inclusion of gt tables in email message bodies. Recent changes to the SCSS file (particularly the addition of a random `id` element) resulted in this function no longer working.

The function needs to be rewritten to take the SCSS changes into account.

### Additional contract requirements

- When `tab_style()` adds `font-size:10px;` to data cells, the resulting HTML must contain `style="padding:10px;margin:10px;text-align:right;font-size:10px;"`.
- The resulting HTML must also contain `style="font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Arial, sans-serif;border-collapse:collapse;margin-left:auto;margin-right:auto;color:#000000;font-size:16px;background-color:#FFFFFF;width:auto;border-top-style:solid;border-top-width:2px;border-top-color:#A8A8A8;"`.
- The resulting HTML must also contain `style="color:#000000;background-color:#FFFFFF;font-size:16px;font-weight:initial;padding:10px;margin:10px;text-align:right;"`.
