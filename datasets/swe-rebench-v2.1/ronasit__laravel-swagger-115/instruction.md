Custom header key for security
I use custom key for token-header, how i can set this name in config?
![image](https://github.com/RonasIT/laravel-swagger/assets/116457711/29a08027-4860-407f-8cdf-5e6ce1a9965d)

..jwt option give standart header name, but i need set another name

### Additional contract requirements

The name of the token header for a security driver is set through the `name` entry of that driver in the `auto-doc` configuration's `security_drivers` section (for example `auto-doc.security_drivers.jwt.name`). The generated security definition uses that configured name.

When a request carries a token in the configured security header, that operation is recorded as secured.
