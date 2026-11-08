Add a method for outputting a plain JS object (PR welcome)
Feature request:

I think it would really benefit this module to formalize the output of a plain javascript object. I know the little one-liner [HIDDEN] but boy, that feels like an opaque weird thing to have in my app code. The need for POJOs is frequent, for instance, using the hapijs server if I attempt to bring any `node-config` object into a config, hapi will fail on the schema validations because of all the additional methods.

Other libraries, such as immutable, that do large amounts of manipulation on objects offer a `toJS` method, which makes a lot of sense to me. [HIDDEN], but I think ideally it would access the hidden internal variables and output those directly.

Going even further, I'd make the case that _any_ invocation of `.get()` should actually output a POJO. It feels highly unnatural to me to be carrying around all this baggage when I've clearly made the choice to only grab a portion of my config.

### Additional contract requirements

- Provide a public function `toObject()` on the configuration utilities, accessible as `config.util.toObject`.
- When called without arguments, `toObject()` returns a deep-cloned plain JavaScript object (POJO) representing the entire configuration. The returned value is not an instance of the `Config` constructor.
