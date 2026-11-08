[PARSE BUG]: template with trailing parameter pack
### Problem description

... or something, it's weird.

### C++ code that can't be parsed correctly (please double-check that https://robotpy.github.io/cxxheaderparser/ has the same error)

```text
template <typename ModuleTranslation, typename... ModuleTranslations>
SwerveDriveKinematics(ModuleTranslation, ModuleTranslations...)
    -> SwerveDriveKinematics<1 + sizeof...(ModuleTranslations)>;
```
