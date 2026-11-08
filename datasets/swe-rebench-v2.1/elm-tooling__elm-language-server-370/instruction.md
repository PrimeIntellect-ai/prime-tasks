Type inference gets confused by aliases
Consider these two modules:

```
module LocalizedHtml exposing (Html, Language(..), div, text)

import Html


type Language
    = Italian
    | English


type alias Html a =
    Language -> Html.Html a


type alias Attribute a =
    Language -> Html.Attribute a


div : List (Attribute msg) -> List (Html msg) -> Html msg
div attributes children language =
    Html.div (List.map (\a -> a language) attributes) (List.map (\c -> c language) children)


text : String -> String -> Html msg
text en it language =
    Html.text <|
        case language of
            English ->
                en

            Italian ->
                it

```

and

```
module Main exposing (main)

import LocalizedHtml exposing (Html, Language(..), div, text)


main =
    div [] [ hello, world ] English


hello : Html msg
hello =
    text "Hello" "Ciao"


world =
    text "World" "Mondo"
```

notice how `Main` does *not* import `Html`.

## Expected Behavior
The type of `world` is inferred to be `Html msg`.

## Current Behavior
The type of `world` is inferred to be `Language -> Html msg`.

## Context
I'm wrapping `elm-ui` to add translations.

Incorrect unused_value_contructor diagnostics
Italian and English are both incorrectly marked as unused.

```elm
type Language
    = Italian
    | English


text : String -> String -> Html msg
text en it language =
    Html.text <|
        case language of
            English ->
                en

            Italian ->
                it
```
