mix gen.auth creates live views in parent folder instead of using its own like the other
### Environment

* Elixir version (elixir -v): Elixir 1.16.2 (compiled with Erlang/OTP 26)
* Phoenix version (mix deps): 1.7.14

### Actual behavior

When using mix gen.auth it polutes the live folder instead of putting its files into a seperate one, like all the other gen tools do.

$ mix phx.new test
$ mix phx.gen.live TestObject [...]
$ mix phx.gen.auth Access User users


➜  test_web tree
```
.
├── components
│   ├── core_components.ex
│   ├── layouts
│   │   ├── app.html.heex
│   │   └── root.html.heex
│   └── layouts.ex
├── controllers
│   ├── error_html.ex
│   ├── error_json.ex
│   ├── page_controller.ex
│   ├── page_html
│   │   └── home.html.heex
│   ├── page_html.ex
│   └── user_session_controller.ex
├── endpoint.ex
├── gettext.ex
├── live
│   ├── other_object_live
│   │   ├── form_component.ex
│   │   ├── index.ex
│   │   ├── index.html.heex
│   │   ├── show.ex
│   │   └── show.html.heex
│   ├── test_object_live
│   │   ├── form_component.ex
│   │   ├── index.ex
│   │   ├── index.html.heex
│   │   ├── show.ex
│   │   └── show.html.heex
│   ├── user_confirmation_instructions_live.ex
│   ├── user_confirmation_live.ex
│   ├── user_forgot_password_live.ex
│   ├── user_login_live.ex
│   ├── user_registration_live.ex
│   ├── user_reset_password_live.ex
│   └── user_settings_live.ex
├── router.ex
├── telemetry.ex
└── user_auth.ex

```

### Expected behavior

Use a seperate folder

### Additional contract requirements

- For `mix phx.gen.auth Access User users`, generate the LiveViews under `lib/my_app_web/live/user_live/` as `registration.ex`, `login.ex`, `reset_password.ex`, `forgot_password.ex`, `settings.ex`, `confirmation.ex`, and `confirmation_instructions.ex`, and generate their tests under `test/my_app_web/live/user_live/` with the corresponding `_test.exs` filenames. Use the `UserLive.Registration`, `UserLive.Login`, `UserLive.ForgotPassword`, `UserLive.ResetPassword`, `UserLive.Settings`, `UserLive.Confirmation`, and `UserLive.ConfirmationInstructions` modules in the generated routes. Do not also generate these auth LiveView source files directly under `lib/my_app_web/live/`.
