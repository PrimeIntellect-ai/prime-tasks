`conform` is converting MapSets to Lists in nested schema
Example taken from my code in another issue (#30).

```elixir
iex> Todo.gen() |> Enum.take(1) |> IO.inspect() |> conform(coll_of(Todo.s()))
[
  %Todo{
    what: "Watch movie",
    when: "Sun",
    who: #MapSet<[
      %Person.Student{name: "Prudence", school: "Academy of the Unseen Arts"},
      %Person.Programmer{
        languages: #MapSet<["Elixir", "Elm", "Haskell"]>,
        name: "Chris",
        university: %Algae.Maybe.Nothing{}
      }
    ]>
  }
]

{:ok,
 [
   %Todo{
     what: "Watch movie",
     when: "Sun",
     who: [
       %Person.Student{name: "Prudence", school: "Academy of the Unseen Arts"},
       %Person.Programmer{
         languages: ["Elixir", "Elm", "Haskell"],
         name: "Chris",
         university: %Algae.Maybe.Nothing{}
       }
     ]
   }
 ]}
```

Issue seems to be when MapSets are nested inside other collections (including lists). For example, here (after revising the code) only `languages` is expected to be a MapSet:

```elixir
iex> Todo.gen() |> Enum.take(1) |> List.first() |> IO.inspect() |> conform(Todo.s())
%Todo{
  what: "Grocery shop",
  when: "Tue",
  who: [
    %Person.Programmer{
      languages: #MapSet<["Cobol", "Elm"]>,
      name: "Wojtek",
      university: %Algae.Maybe.Nothing{}
    },
    %Person.Student{name: "Sabrina", school: "Baxter High School"}
  ]
}

{:ok,
 %Todo{
   what: "Grocery shop",
   when: "Tue",
   who: [
     %Person.Programmer{
       languages: ["Cobol", "Elm"],
       name: "Wojtek",
       university: %Algae.Maybe.Nothing{}
     },
     %Person.Student{name: "Sabrina", school: "Baxter High School"}
   ]
 }
}
```
