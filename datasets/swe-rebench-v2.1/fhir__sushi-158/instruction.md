Don't inherit potentially irrelevant metadata from parents
This issue stems from the conversation of #128.  The general discussion was around clearing inherited metadata that causes issues in the IG Publisher or is potentially irrelevant to the profile.  The main concern of #128 was the `"comment"` field, which is in `ElementDefinition`.  We've currently decided _not_ to address that because clearing comments would cause _many_ differential elements.

This issue is to point out that the top-level metadata of profiles and extensions still inherits many fields that are potentially irrelevant or wrong for the profile/extension.  We should remove those.  I proposed an approach on Zulip here: https://chat.fhir.org/#narrow/stream/179252-IG-creation/topic/Bad.20links.20on.20Detailed.20Description.20tab/near/186460459

I've also copied the approach in case something happens to the zulip:

* **id** - overwrite w/ new id
* **meta** - clear
* **implicitRules** - clear
* **language** - clear
* **text** - clear
* **contained** - clear
* **extension** - clear (see https://github.com/FHIR/sushi/issues/116)
* **modifierExtension** - clear
* **url** - overwrite w/ new url
* **identifier** - clear
* **version** - overwrite w/ IG version (author can override if maintaining per-profile versions)
* **name** - overwrite w/ new name
* **title** - clear or overwrite w/ new title (if applicable)
* **status** - currently defaults to `active` but FSH should add (required?) keyword
* **experimental** - clear
* **date** - clear
* **publisher** - clear (or overwrite w/ publisher from config?)
* **contact** - clear (or overwrite w/ contributors from config?)
* **description** - clear or overwrite w/ new description (if applicable)
* **useContext** - clear
* **jursidiction** - clear
* **purpose** - clear
* **copyright** - clear
* **keyword** - clear or keep? Would parent keywords still be applicable to child profiles?
* **fhirVersion** - set to target version (should match anyway)
* **mapping** - keep (assuming mappings are still valid and because removing them would require use to remove mappings from every element, creating tons of diffs)
* **kind** - keep (this should not change)
* **abstract** - keep or set to false.  If you set an abstract profile as a parent should you need to explicitly toggle abstractness to `false`?  Or should we default to `false`?
* **context** - keep (assuming context is still valid for child extensions)
* **contextInvariant** - keep (assuming context is still valid for child extensions)
* **type** - keep (this should not change for profiles or extensions)
* **baseDefinition** - overwrite w/ the parent URL of the new profile/extension
* **derivation** - set to constraint (so far, SUSHI only supports constraints)
* **snapshot** - keep, but elements will obviously be overwritten by constraints
* **differential** - clear, as the differential starts from scratch to reflect changes the profile has made to the parent
