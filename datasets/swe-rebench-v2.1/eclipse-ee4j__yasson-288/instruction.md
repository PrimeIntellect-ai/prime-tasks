Order of kv-pairs wrong when using custom naming and @JsonbPropertyOrder
When you use a custom naming strategy, Yasson 1.0.3 does not handle @JsonbPropertyOrder correctly. According to the Javadoc of @JsonbPropertyOrder:

> Order in which properties are serialized. **Names must correspond to original names defined in Java class before any customization applied.**

But when I try this, it does not work: the order of the key-value pairs in JSON is different than what I specify with @JsonbPropertyOrder. To make it work, I must use the translated names instead of the original Java property names, which is against what the Javadoc documentation says.

I've found issue #23 but this does not seem to be fixed in Yasson 1.0.3.

See attached example project: [yasson-bug.zip](https://github.com/eclipse-ee4j/yasson/files/3051727/yasson-bug.zip)
