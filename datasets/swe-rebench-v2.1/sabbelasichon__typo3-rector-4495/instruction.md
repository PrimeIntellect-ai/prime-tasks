[BUG] ConstantsToBackedEnumValueRector migrates incorrectly
### Minimal PHP Code Causing Issue

This rule migrates the following constants to enums:

`TYPO3\CMS\Core\Resource\File::FILETYPE_*`

Example:

```diff
- TYPO3\CMS\Core\Resource\File::FILETYPE_IMAGE => [
+ TYPO3\CMS\Core\Resource\FileType::IMAGE => [
```

The problem is that those constants were integers and the replacement is an enum (object) with a corresponding integer value. This however breaks most, if not all code.

### Applied rules

`\Ssch\TYPO3Rector\General\Renaming\ConstantsToBackedEnumValueRector`

### Expected Behaviour

Expected behaviour would be to replace int constant usages with int enum values:

```diff
- TYPO3\CMS\Core\Resource\File::FILETYPE_IMAGE => [
+ TYPO3\CMS\Core\Resource\FileType::IMAGE->value => [
```

### Package Version

2.0.7

### PHP Version

8.2.0

### TYPO3 Version

13.4.0

### Notes

See: #4060
See: #3698
See: #4449
See: #3698
