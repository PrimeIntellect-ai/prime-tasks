IsCurrency symbol validation error
Hi devs,

I'm trying use BRL currency in @IsCurrency options, but when I use this setting the validator fails:

```json
{
	symbol: 'R$',
	require_symbol: true,
	allow_space_after_symbol: true,
	symbol_after_digits: false,
	allow_negatives: false,
	parens_for_negatives: false,
	negative_sign_before_digits: false,
	negative_sign_after_digits: false,
	allow_negative_sign_placeholder: false,
	thousands_separator: '.',
	decimal_separator: ',',
	allow_decimal: true,
	require_decimal: true,
	digits_after_decimal: [2],
	allow_space_after_digits: false,
}
```

Value: `R$ 1.400,00`

```
"statusCode": 400,
    "message": [
        "monthyMoneyGoal must be a currency"
    ],
    "error": "Bad Request"
```

But changing symbol to `$` it works:

```json
{
	symbol: '$',
	require_symbol: true,
	allow_space_after_symbol: true,
	symbol_after_digits: false,
	...
}
```

Value: `$ 1.400,00`

```
"statusCode": 200,
    "message": [
        "Successful update"
    ],
```

Changing symbol to `$R` it unbelievably too works!

Why? Where is error?

PS: My app uses single quotes in Prettier Formatter
