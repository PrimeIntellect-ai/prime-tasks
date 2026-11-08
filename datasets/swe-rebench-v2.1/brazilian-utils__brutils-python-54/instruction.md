Add `formatCPF` method
In order to make it with the same API as [js brutils](https://brazilian-utils.com.br/#/utilities?id=formatcpf)

### Additional contract requirements

- `format_cpf` is available as both `brutils.cpf.format_cpf` and `brutils.format_cpf`. Given an 11-digit numeric string whose digits are not all identical, it returns the standard `XXX.XXX.XXX-YY` representation. Formatting does not require the CPF check digits to be valid. Inputs that cannot be displayed, including inputs with non-digit characters, a length other than 11, or eleven identical digits, return `None`.
