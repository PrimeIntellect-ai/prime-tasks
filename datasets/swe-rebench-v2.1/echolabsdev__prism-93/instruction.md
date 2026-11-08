Dynamic provider configs
### Discussed in https://github.com/echolabsdev/prism/discussions/89

<div type='discussions-op-text'>

<sup>Originally posted by **binaryfire** December  7, 2024</sup>
Great package TJ!

Would it be possible to add a way to use dynamic provider configs without having to override config values? Config overrides are really problematic with Octane.

For example, this is how the Socialite Providers package does it:  https://socialiteproviders.com/usage/#overriding-a-config

This would make it easier to use the package in a multi-tenant context, where each tenant brings their own keys.

</div>

### Additional contract requirements

Text and structured generation requests must be able to receive provider configuration overrides for that request. Overrides take precedence over matching provider defaults while leaving other defaults available. Applying an override must not modify shared provider configuration or affect a later request that does not supply that override. This behavior applies to built-in providers as well as custom providers.

The request-level overrides are supplied through the fluent `usingProviderConfig(array $config)` method on text and structured generators.
