picture & img element improvements
Hi @markuswustenberg , I am really happy that I discovered your project here and I am excited to put it to good use and bring it to production for several of my clients.
I love Go, compiled language, type safety and the great re-usability that we get by using Go components.
I can only see one spot where some love is missing, and that is in the image elements.

I particularly make heavy use of the `picture` element and the `img` element in some sites. Some points I have noticed are:
- Missing `srcset` attribute in `picture` element
- Missing `loading` attribute in `img` element

With those 2 additions I can really bring this to all my current and future projects. If you don't have the time to implement this, I would also not mind tips on how to proceed adding this to the codebase, although I would be a bit lost and it would take some time.

Thanks in advance man! And thanks for this wonderful creation!
Greetings from NL 🇳🇱

### Additional contract requirements

- Provide `html.SrcSet(v string) g.Node`, which emits a `srcset` attribute with value `v` for picture-related markup.
- Provide `html.Loading(v string) g.Node`, which emits a `loading` attribute with value `v` for `img` markup.
