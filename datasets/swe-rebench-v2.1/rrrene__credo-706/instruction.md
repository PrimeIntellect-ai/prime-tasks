ModuleDependencies doesn't ignore umbrella test folders by default
### Environment

* Credo version (`mix credo -v`): `1.1.5`
* Erlang/Elixir version (`elixir -v`): Erlang/OTP 21 [erts-10.2.2] Elixir 1.9.0 (compiled with Erlang/OTP 20)
* Operating system: Mac OS 10.13.6

### What were you trying to do?

run `ModuleDependencies` check

### Expected outcome

Ignores umbrella test folders by default

### Actual outcome

warns on too many dependencies in umbrella tests.
