@Published property wrapper doesn't work
I see in project's release notes that `@Published` doesn't work yet, which is confusing as it's available in the list of public module declarations. In addition, the property is not recognized even when `import OpenCombine` is present in the file. Would be great to know if there are some specific reasons for that, otherwise, just creating an issue to track this. Maybe someone could provide more info or directions on the best way to fix this 🙏

### Additional contract requirements

The projected publisher of a usable `@Published` class property reports its current value to a subscriber and publishes subsequent property updates.

When an `objectWillChange` notification is emitted while assigning to an `@Published` property, the notification occurs before the property's stored value changes. A custom `objectWillChange` publisher is not required to emit a notification for every `@Published` assignment.
