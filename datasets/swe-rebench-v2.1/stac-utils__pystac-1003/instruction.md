Add extra_fields to extensions.item_assets.AssetDefinition
The Item Assets Definition Extension states:

> Other custom fields, or fields from other extensions may also be included in the Asset object.

However, there is not currently a Pythonic way to do this in PySTAC. The `AssetDefinition.create` and `AssetDefinition.apply` methods only accept `title`, `description`, `media_type` and `roles` arguments, so the only way to add something like a `raster:bands` field to the Asset Definition is by initializing it with a dictionary that includes that property.

It seems like it would be helpful to have an `extra_fields` argument to both `create` and `apply` that allows additional properties to be passed in.
