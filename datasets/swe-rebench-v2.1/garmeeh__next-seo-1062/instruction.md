next-seo dangerouslySetAllPagesToNoFollow and dangerouslySetAllPagesToNoIndex does not allow override
According to the documentation for next-seo plugin, we should be able to override [dangerouslySetAllPagesToNoFollow](https://github.com/garmeeh/next-seo#dangerouslysetallpagestonofollow) and [dangerouslySetAllPagesToNoIndex](https://github.com/garmeeh/next-seo#dangerouslysetallpagestonoindex) defined in \<DefaultSeo\> component on a page level via \<NextSeo\> component:

"You can still override this at a page level if you have a use case to index a page. This can be done by setting noindex: false."


I have added dangerously set options in default seo in _app.tsx:
```
<DefaultSeo
                  dangerouslySetAllPagesToNoIndex={true}
                  dangerouslySetAllPagesToNoFollow={true}
  />
```

and set nofollow/noindex to false for the pages I need indexed:

```
   <NextSeo
                nofollow={false}
                noindex={false}
            />
```

yet I'm getting noindex/nofollow meta tags in rendered pages which have nofollow/noindex set to false:

```
<meta name="robots" content="noindex,nofollow">
<meta name="googlebot" content="noindex,nofollow">
```

when the expected tags should be:
```
<meta name="robots" content="index,follow">
<meta name="googlebot" content="index,follow">
```

Please let me know how this could be resolved, any help appreciated
