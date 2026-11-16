$map skipping every other element
Hello,

I have these 2 transforms that i would expect to be equivalent but they produce different results. Im using this context.
```json
[
  "Felicia Saunders",
  "Jimmy Schultz",
  "Dolores Figueroa",
  "Craig Moreno",
  "Lindsey Hall",
  "Bonnie Russell",
  "Kristin Stewart",
  "Owen Reid",
  "Brenda Sherman",
  "Dwayne Baldwin"
]
```
The first transform is the one that seems to be buggy.
`
$map($, $match(?, /^(\w*\s\w*)/))
`
Results
```json
[
  [
    {
      "match": "Felicia Saunders",
      "index": 0,
      "groups": [
        "Felicia Saunders"
      ]
    }
  ],
  [],
  [
    {
      "match": "Dolores Figueroa",
      "index": 0,
      "groups": [
        "Dolores Figueroa"
      ]
    }
  ],
  [],
  [
    {
      "match": "Lindsey Hall",
      "index": 0,
      "groups": [
        "Lindsey Hall"
      ]
    }
  ],
  [],
  [
    {
      "match": "Kristin Stewart",
      "index": 0,
      "groups": [
        "Kristin Stewart"
      ]
    }
  ],
  [],
  [
    {
      "match": "Brenda Sherman",
      "index": 0,
      "groups": [
        "Brenda Sherman"
      ]
    }
  ],
  []
]
```
This produces what i would expect
`
$map($, function($i){
    $match($i, /^(\w*\s\w*)/)
})
`
Results
```json
[
  [
    {
      "match": "Felicia Saunders",
      "index": 0,
      "groups": [
        "Felicia Saunders"
      ]
    }
  ],
  [
    {
      "match": "Jimmy Schultz",
      "index": 0,
      "groups": [
        "Jimmy Schultz"
      ]
    }
  ],
  [
    {
      "match": "Dolores Figueroa",
      "index": 0,
      "groups": [
        "Dolores Figueroa"
      ]
    }
  ],
  [
    {
      "match": "Craig Moreno",
      "index": 0,
      "groups": [
        "Craig Moreno"
      ]
    }
  ],
  [
    {
      "match": "Lindsey Hall",
      "index": 0,
      "groups": [
        "Lindsey Hall"
      ]
    }
  ],
  [
    {
      "match": "Bonnie Russell",
      "index": 0,
      "groups": [
        "Bonnie Russell"
      ]
    }
  ],
  [
    {
      "match": "Kristin Stewart",
      "index": 0,
      "groups": [
        "Kristin Stewart"
      ]
    }
  ],
  [
    {
      "match": "Owen Reid",
      "index": 0,
      "groups": [
        "Owen Reid"
      ]
    }
  ],
  [
    {
      "match": "Brenda Sherman",
      "index": 0,
      "groups": [
        "Brenda Sherman"
      ]
    }
  ],
  [
    {
      "match": "Dwayne Baldwin",
      "index": 0,
      "groups": [
        "Dwayne Baldwin"
      ]
    }
  ]
]
```
Does this seem like a bug or is there something im missing?

Thanks
