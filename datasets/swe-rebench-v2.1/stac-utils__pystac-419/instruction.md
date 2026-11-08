ExtensionManagementMixin.add_to should be idempotent
Calling the `add_to` method on a concrete sub-class of `pystac.extensions.base.ExtensionManagementMixin` multiple times will add that extension's schema URI to the `stac_extensions` list multiple times.

We should ensure that schema URIs are only added to an object's `stac_extensions` list if they are not already there.

Alternatively, we could make `stac_extensions` a `set`, since there shouldn't ever be a case where schema URIs are duplicated. This would involve changing the way values are added to that field throughout the code base, and may have implications on how objects are serialized to JSON, but would probably improve performance over checking if an element is in the list.
