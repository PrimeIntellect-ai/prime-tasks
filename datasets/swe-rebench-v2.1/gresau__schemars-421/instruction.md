[Feature Request] Option to not add Enum variant names to titles
Thank you for the wonderful crate.

Since 1.0.0-alpha.19, Enum variants are now added to the title by default (https://github.com/GREsau/schemars/pull/413).

Can this be made optional?


When providing hover functionality using JSON Schema, unintended hover content may occur.

![Image](https://github.com/user-attachments/assets/63c38d3f-a153-470a-af59-33b8260d7609)

As expected, the title of the relevant item in allOf should appear, but the title in allOf overwrites the title of the item.

In 1.0.0-alpha.18

![Image](https://github.com/user-attachments/assets/3631559c-c861-4e70-97e1-19b0cdc26c38)

### Additional contract requirements

`SchemaSettings` exposes a boolean `untagged_enum_variant_titles` setting. When enabled, automatically generated untagged enum variant names are included as schema `title` values; when disabled, those automatically generated titles are omitted. The default setting value is not specified.
