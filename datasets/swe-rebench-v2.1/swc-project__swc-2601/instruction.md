Is swc support options like Babel-loader "sourceType":  "unambiguous" ?
<!--
If you are using swc at work, please considering adding your company to https://swc.rs/users/
If then, your issue will be fixed more quickly.
-->

**Describe the feature**
Is there an option like babel-loader `sourceType: "script" | "module" | "unambiguous"`

**Babel plugin or link to the feature description**
https://babeljs.io/docs/en/options#sourcetype

**Additional context**

### Additional contract requirements

- Add a public enum `IsModule` in module `swc::config` with variants `Bool(bool)` and `Unknown`. `Bool(true)` forces module parsing, `Bool(false)` forces script parsing, and `Unknown` enables automatic detection of whether the source is a module or a script.
- `IsModule` implements `Serialize` and `Deserialize`. In JSON, `Bool(b)` is represented as the boolean `b`, and `Unknown` is represented as the string `"unknown"`; deserialization accepts a boolean or the string `"unknown"`.
- The public field `is_module` of `swc::config::Options` has type `IsModule`, and `Options::default()` sets it to `IsModule::Bool(true)`.
- Add a public method `swc::Compiler::parse_js(&self, fm: Arc<SourceFile>, handler: &Handler, target: EsVersion, syntax: Syntax, is_module: IsModule, parse_comments: bool) -> Result<Program, Error>` that parses the file according to `is_module`: `Bool(true)` produces a module, `Bool(false)` produces a script, and `Unknown` auto-detects between the two.


- Deserializing `swc::config::Options` from JSON with the property `"isModule": "unknown"` sets `is_module` to `IsModule::Unknown`.
