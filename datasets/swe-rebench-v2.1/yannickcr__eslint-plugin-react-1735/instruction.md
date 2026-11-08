forbid-component-props should have a component whitelist
For custom components it makes sense to have the rule, but when using third-party components violating the rule (`ReactModal` using `className` is probably one of the more prominent examples) there isn't much you can do about it...

Having to add `eslint-disable react/forbid-component-props` comments isn't a very pretty solution.

### Additional contract requirements

- Configure the whitelist with `forbid` entries shaped as `{ propName: 'className', allowedFor: ['ReactModal'] }`. With this configuration, `<ReactModal className="foo" />` is allowed, while `<Foo className="foo" />` and `<this.ReactModal className="foo" />` remain violations.
