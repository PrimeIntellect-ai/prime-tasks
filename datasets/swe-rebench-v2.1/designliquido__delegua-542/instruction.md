Expandir avaliação semântica de condição de `enquanto` para `Agrupamento` e `Binario`
Em:

```js
enquanto a != 5 {
    escreva(a)
    a++
}
```

A condição é:

![image](https://github.com/DesignLiquido/delegua/assets/53848829/5a7125b9-d6ae-44bd-be42-f0b7934ac3c2)

Em:

```js
enquanto (a != 5) {
    escreva(a)
    a++
}
```

A condição é:

![image](https://github.com/DesignLiquido/delegua/assets/53848829/e365206f-ee27-4d72-87a2-22d8b9ccd11d)

A avaliação semântica de Delégua até então só aceita algo como:

```js
enquanto (a) {
    escreva(a)
    a++
}
```
