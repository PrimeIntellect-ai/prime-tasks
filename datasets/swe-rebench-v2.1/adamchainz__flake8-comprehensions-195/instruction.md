False positive on C404
I have a block of code that looks like:

    instance_kwargs = dict([
        key_value.split('=')
        key_value in full_lookup.split(':')[1].split('&')
    ])

This is being marked as  C404: unnecessary list comprehension.

However, I don't believe it's possible to use a single dict comprehension to perform this.

(I'm not saying it's great code, btw...)
