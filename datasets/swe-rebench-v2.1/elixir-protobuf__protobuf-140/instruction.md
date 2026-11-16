Repeated enum fields do not generate proper typespecs
I'm not 100% sure about this sorry so this is more a question than an statement

In the case we have

```protobuf
syntax = "proto3";
package test;

message Salute {
    repeated Word words = 1;
}

enum Word {
  WORD_HI = 0;
  WORD_BYE = 1;
  WORD_MISS = 2;
  WORD_MR = 3;
}
```

The generate generates the following

```elixir
defmodule Test.Salute do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
    words: [[Test.Word.t()]],
  }

  defstruct [
    :words
  ]

  field :words, 0, repeated: true, type: Test.Word, enum: true
end

defmodule Test.Word do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3

  @type t ::
          integer
          | :WORD_HI
          | :WORD_BYE
          | :WORD_MISS
          | :WORD_MR

  field :WORD_HI, 0
  field :WORD_BYE, 1
  field :WORD_MISS, 2
  field :WORD_MR, 3
end
```

Would you mind to confirm that is the expected typespec instead just `words: [Test.Word.t()],` so just one single `[` instead of `[[`

### Additional contract requirements

- For a repeated enum field, the generated typespec must spell the enum type without parentheses, e.g. `a: [FooBar.AbCd.EnumFoo.t]`.
