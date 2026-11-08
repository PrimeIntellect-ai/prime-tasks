#[Inject] on readonly constructor-promoted properties
Injection currently only works when the Inject attribute is used as a method attribute on the constructor.

When the Inject attribute is used on the readonly constructor-promoted property, PHP-DI attempts to set the value through ```\DI\Definition\Resolver\ObjectCreator::setPrivatePropertyValue()``` but fails because ```setValue()``` can't be called on a readonly property.
