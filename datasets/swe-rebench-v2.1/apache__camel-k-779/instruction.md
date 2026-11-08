Integration naming issues with numbers in them
If you create integrations with the same name but ending in a number the number is ignored and identical integrations are created linked to the *same* deployed Pod.

For example:

~/camelk/kamel run Sample.java --name=looknoeap1

Results in a deployment occurring with the name 'looknoeap'. If I then do:

~/camelk/kamel run Sample.java --name=looknoeap2

I get - integration "looknoeap" updated

For some reason the naming convention is dropping numbers at the end - it also ignores '-', i.e. --name=looknoeap-2 resolves to 'looknoeap' as well.

However, if I then do:

~/camelk/kamel run Sample.java --name=looknoeap-two

It creates an integration called 'looknoeap-two.

### Additional contract requirements

- Sanitizing the name `1foo-bar2` must return `1foo-bar2`.
