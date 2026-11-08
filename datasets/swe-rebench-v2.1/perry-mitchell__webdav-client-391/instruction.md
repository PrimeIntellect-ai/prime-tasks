Support xml attributes
## Xml example
```xml
<?xml version="1.0"?>
<d:multistatus
	xmlns:d="DAV:"
	xmlns:s="http://sabredav.org/ns"
	xmlns:oc="http://owncloud.org/ns"
	xmlns:nc="http://nextcloud.org/ns">
<d:response>
		<d:href>/remote.php/dav/files/admin/benjamin-lehman-xnTcEJm5IZw-unsplash.jpg</d:href>
		<d:propstat>
			<d:prop>
				<nc:system-tags>
					<nc:system-tag oc:can-assign="true" oc:id="321" oc:user-assignable="true" oc:user-visible="true">Test</nc:system-tag>
				</nc:system-tags>
			</d:prop>
			<d:status>HTTP/1.1 200 OK</d:status>
		</d:propstat>
	</d:response>
</d:multistatus>
```

## Issue
Currently, the `fast-xml-parser` ignore attributes.
A quick test, passing [the following options](https://github.com/perry-mitchell/webdav-client/blob/193268946a608708733a15612caaab13f93b156c/source/tools/dav.ts#L25-L30) would allow us to retrive the attributes like so
```js
        [HIDDEN]
```
![image](https://github.com/user-attachments/assets/632ee76f-bc79-4f9c-8fe1-8805f1fd28c2)


I think adding a proper method to process those would be best, so we can keep the namespaces and avoid conflicts?

### Additional contract requirements

- Parsed XML attributes must be exposed on the corresponding element object, alongside the element's text content.
- Attribute names are exposed using their local name, with any namespace prefix removed (for example `oc:can-assign` is exposed as `can-assign`).
- Attribute values are exposed as strings, except that the values `"true"` and `"false"` are coerced to the booleans `true` and `false`.
- A boolean attribute written without a value (for example `z:checked`) is exposed as the boolean `true`.
- The text content of an element that also carries attributes is exposed under the `text` key.
- Namespace prefixes are removed from element names in parsed XML output (for example, `z:system-tags` is exposed as `system-tags`).
