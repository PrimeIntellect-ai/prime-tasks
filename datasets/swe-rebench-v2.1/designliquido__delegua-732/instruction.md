Laço para cada só executa apenas uma vez se estiver dentro de outro laço
```js
var numeros = [1, 2, 3, 4]

para cada numero de numeros {
    para cada numero de numeros {
        escreva(numero)
    }
}

```

![Image](https://github.com/user-attachments/assets/94b3ec4d-4b6d-418d-8ace-ebb8e291bba8)

O resultado esperado era pra ser
```js
1
2
3
4
1
2
3
4
1
2
3
4
1
2
3
4
```
