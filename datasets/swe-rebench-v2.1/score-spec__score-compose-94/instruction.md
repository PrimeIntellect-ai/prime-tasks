[feature request] support access to `${metadata.annotations.key\.com/key}` annotation placeholders in the substituion routines
We allow `${metadata...} placeholders to access keys and values under the metadata section. While we support escaping .'s for the `key\.com` part, we don't support the forward slash in the supported substitution key format. We should fix that :)
