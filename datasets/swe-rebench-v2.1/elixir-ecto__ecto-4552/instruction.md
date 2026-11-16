Intermittent "invalid association" warnings at compile time
### Elixir version

1.15.6

### Database and Version

PostgreSQL 15.4

### Ecto Versions

3.10.3

### Database Adapter and Versions (postgrex, myxql, etc)

Postgrex

### Current behavior

For a few months now, we've been seeing the following warning show up in our logs intermittently when compiling or running `mix test`:

```warning: invalid association `family` in schema Core.UserDevices.UserDevice: associated module Core.Families.Family is not an Ecto schema
  lib/core/user_devices/user_device.ex:1: Core.UserDevices.UserDevice (module)```

Sometimes there are multiple warnings for a few schemas, sometimes none. The subject of their complaint is often this Family module, though it sometimes varies and can apply to any one of our schemas. I've traced the source of the message to the `after_compile_validation` functions in `association.ex` in Ecto, where it seems that for some reason, Elixir doesn't believe the Family module has `__schema__` exposed. It's definitely working as expected, though, and the app is functioning fine. So this warning seems to be a false alarm.

I assume that something strange is going on here with compilation order, but am unsure. Since it's intermittent, I don't have a simple code example that can reproduce the issue, but I saw [this past issue](https://github.com/crewfinance/ecto/commit/c66ab5f89ef348c7f520f427001c33d95a78bd2e) that seems very similar, as well as [this recent change](https://github.com/elixir-ecto/ecto/commit/31b7e2e5ea035974f1a23adc83d203b3656582ea#diff-175cbcdf996d9bf56858257b3de96731887a2a5e97d26ce474919488499121ccR2247) one call upstream from our issue and am crossing my fingers that others may have reported something similar recently, resulting in this change? Here's a simplified version of our Family schema that is showing the issue (though as I mentioned, any of our Ecto schemas at varying times will sometimes show up, seemingly depending on compile order).

```defmodule Core.Families.Family do
  @moduledoc """
  Representation of an entire family account.
  """

  # Pulls in the LetMe Ecto authorization library and some boilerplate for it.
  use Core.SecuredEctoSchema
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias __MODULE__
  alias Core.Accounts.Account
  alias Core.Addresses.Address
  alias Core.Cards.Card
  alias Core.Transfers.Transfer
  alias Core.UserDevices.UserDevice
  alias Core.Users.User

  @statuses [
    :activated,
    :deactivated,
    :failed
  ]

  schema "families" do
    field :uuid, Ecto.UUID, autogenerate: true

    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :activated

    has_many :accounts, Account
    belongs_to :address, Address
    has_many :cards, Card
    has_many :devices, UserDevice
    has_many :transfers, Transfer
    has_many :users, User

    timestamps type: :utc_datetime_usec
  end

  @doc """
  Family changeset
  """
  def changeset(%Family{} = family, params \\ %{}) do
    cast(family, params, Family.__schema__(:fields))
  end

  @impl LetMe.Schema
  def scope(q, %User{family_id: family_id}, _opts \\ []) do
    where(q, id: ^family_id)
  end
end
```

The other schemas referencing (in the error above, UserDevice) simply have an alias to Core.Families.Family and then reference it with `belongs_to :family, Family`. Only things of note are that our schemas often use the LetMe library for authorization, and TypedEctoSchema to generate types for specs. Neither seem related since removing them from the schemas in the warning doesn’t change the warning, but worth mentioning just in case since I've never tried entirely pulling them from our codebase!

If this isn't enough information to confirm a bug since I'm unable to reproduce, feel free to close--I definitely recognize this isn't a support forum and I've come with some vague details! But if this is ringing any bells we'd love to help track down what's making Ecto mad! (And to get our logs happy again)!

### Expected behavior

Not seeing a warning for a thing that's a functioning Ecto schema!
