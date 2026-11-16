The keyPrefix argument is ignored in JavascriptLexer, and not in JsxLexer
## To Reproduce

Name this file with .ts extension (configured with JavascriptLexer) and the keyPrefix is ignored, if you use JsxLexer instead, it's works
```typescript
export default function useArticlesFilter() {
  const { t } = useTranslation('filters', { keyPrefix: 'articles' });

  return useMemo(() => {
    return {
      menuTitle: t('menu'),
      badge: {
        Component: ArticlesBadge,
      },
      panel: {
        Component: ArticlesPanel,
        query: ArticlesPanelQuery,
      },
    };
  }, [t]);
}
```

## Expected behavior

Keyprefix should not be ignored

### Additional contract requirements

- `JavascriptLexer` must apply the `keyPrefix` configured through `useTranslation` to the keys it extracts, exactly as `JsxLexer` already does. For example, extracting `const { t } = useTranslation('filters', { keyPrefix: 'articles' }); t('menu')` must yield the entry `{ key: 'menu', namespace: 'filters', keyPrefix: 'articles' }`.
- When several translation functions are created from `useTranslation` with different namespaces and keyPrefixes (for example `const { t: tCommon } = useTranslation('common')`, `const { t: tPrefix } = useTranslation('common', { keyPrefix: 'random' })` and `const { t } = useTranslation('test')`), each alias must be associated with its own namespace and keyPrefix. Keys extracted through an alias must be written to that alias's namespace, and prefixed with that alias's keyPrefix. This applies to both `JavascriptLexer` and `JsxLexer`.
