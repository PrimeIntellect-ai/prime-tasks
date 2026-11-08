Remove TokenCredential::clear_cache()
Caching should be an implementation detail of each credential type. `clear_cache()` is misleading because some credentials don't cache anything, and clearing a cache doesn't guarantee the next `get_token` call will authenticate again or return a new token.
