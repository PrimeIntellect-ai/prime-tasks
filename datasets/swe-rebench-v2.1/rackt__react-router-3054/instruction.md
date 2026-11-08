React checksum fails when using server side rendering and basename
I made a demo repo for the issue https://github.com/wordofchristian/react-router-error-demo

Basically using a basename with react-router it will render the `<Link />` component with a different href between server and client:

```
Warning: React attempted to reuse markup in a container but the checksum was invalid. This generally means that you are using server rendering and the markup generated on the server was not what the client was expecting. React injected new markup to compensate which works but you have lost many of the benefits of server rendering. Instead, figure out why the markup being generated is different on the client or server:
 (client) ><a class="" href="/my-app/" data-reacti
 (server) ><a class="" href="/" data-reactid=".wst
```

The client rendered link has the basename of `/my-app` added correctly, but the server side link does not.

![](http://i.imgur.com/UA1GpkZ.png)

### Additional contract requirements

- When server rendering with a history created with a `basename`, every `<Link>` in the rendered markup must have an `href` that includes that basename, so the server markup matches what the client renders for the same basename.
