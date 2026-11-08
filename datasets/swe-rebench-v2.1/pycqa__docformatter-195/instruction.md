v1.6.4 - Consider Not Capitalizing Proper Nouns if Other Capital Letters Exist in the Word
This one may be a bit opinionated...but when a docstring starts with a proper noun that does not start with a capital letter, docformatter is now capitalizing it.

Example:
```diff
@pytest.fixture(scope="session", autouse=True)
def client():
-    """qBittorrent Client for testing session."""
+    """QBittorrent Client for testing session."""
    client = Client()
```

I can imagine other words like `iOS`, `macOS`, `eBay` etc. being affected.

Since detecting whether a word is a proper noun isn't trivial, perhaps detecting if the first word has other capital letters may be sufficient. Alternatively, saying, "wait on #144" may make sense too.

### Additional contract requirements

Users can prevent a proper noun with internal capitals from being changed when it begins a docstring summary by listing that word with the existing `--non-cap` command-line option. The spelling of a listed word is preserved in the formatted summary; other formatting, including summary punctuation, still applies.
