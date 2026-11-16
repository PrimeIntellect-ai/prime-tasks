setting max_age to nil in put_resp_cookie/4 causes crash
In the example below the cookie is set in the `/set` route but the `fetch_cookies/2` call in the `/read` route crashes because of the nil encoded `max_age`.

I think we should either reject nil `max_age` in the `put_resp_cookie/4`, or gracefully handle this case as if `max_age` was not set (i.e., that max age is for the length of the session).

What do you think?

Code example:
```elixir
Mix.install([
  {:bandit, "~> 1.5"}
])

defmodule Router do
  use Plug.Router

  plug(:set_secret)
  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  def set_secret(conn, _opts) do
    %{conn | secret_key_base: "somesecret"}
  end

  get "/set" do
    conn
    |> put_resp_cookie("foo", 123, sign: true, max_age: nil)
    |> send_resp(200, "Hello, World!")
  end

  get "/read" do
    conn = fetch_cookies(conn, signed: ~w(foo))
    value = Map.fetch!(conn.cookies, "foo")
    send_resp(conn, 200, "Set value = #{value}")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

bandit = {Bandit, plug: Router, scheme: :http, port: 4000}
{:ok, _} = Supervisor.start_link([bandit], strategy: :one_for_one)

# unless running from IEx, sleep idenfinitely so we can serve requests
unless IEx.started?() do
  Process.sleep(:infinity)
end
```

### Additional contract requirements

- `Plug.Conn.put_resp_cookie/4` accepts a `:max_age` option whose value may be `nil`. When `:max_age` is `nil`, the cookie is written as if `:max_age` had not been provided (using the default max age) instead of causing a crash.
- This `nil` `:max_age` handling applies when the cookie is encrypted (`encrypt: true`) as well as when it is signed (`sign: true`).
