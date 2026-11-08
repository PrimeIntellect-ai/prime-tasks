Set schema prefix on insert
Referenced from: https://github.com/phoenixframework/phoenix_ecto/issues/82

### Environment

Elixir: 1.4.2
PostgreSQL 9.6.2
Ecto: 2.1.4
Phoenix:  1.2.3
postgrex 0.13.2
OS: macOS Sierra 10.12.4

### Current behavior

Here is a factory module based off of what is in my app:

    defmodule MyApp.Factory do
      def build(:tenant) do
         %MyApp.Tenant{name: "tenant"}
      end

      def build(:user) do
        %Scalpel.User{username: "example-#{System.unique_integer()}"}
      end

      def build(factory_name, attributes) do
        factory_name |> build() |> struct(attributes)
      end

      def insert!(:tenant) do
        tenant = Repo.insert!(build(:tenant))
        # Runs all of the tenant specific migrations
        MyApp.TenantActions.create_tenant(Repo, tenant)
        tenant
      end

      def insert!(factory_name, attributes \\ [], prefix \\ "public") do
        Repo.insert! build(factory_name, attributes), prefix: prefix
      end
    end

    tenant = insert!(:tenant)
    user = insert(:user, [], build_prefix(tenant))

    let(:response) do
      build_conn |> assign(:current_user, user)
    end

  In a controller we have a plug function that loads the user's profile

    plug :load_profile, "before show" when action in [:show]

    #  We get a failure here in our test because the profile table only
    #  exists under the schema of the tenant.
    def load_profile(%{current_user: user }) do
       user |> Ecto.assoc(:profile) |> Repo.one()
    end

    def load_profile(conn, _opts) do
       cond do
          conn.assigns[:profile] ->
               conn
          profile = load_profile(conn.assigns) ->
            conn |> assign(:profile, profile)
          true ->
              conn |> redirect(to: page_path(conn, :index)) |> halt()
       end
    end

### Expected Behavior

My expectation is that if I have inserted the user with the tenant prefix, it should update the record with the schema it has been given.
