# Meyui Beuyi: Caos no Rio

Protótipo 3D de aventura cartunesca no navegador: explore uma cidade costeira fictícia, colete petiscos, provoque caos inofensivo e compre melhorias para o Meyui Beuyi.

## Rodar localmente

```powershell
npm start
```

Abra `http://127.0.0.1:8000`.

## Controles

- `WASD` ou setas: andar na direção da câmera
- Clique e arraste no mundo: girar a câmera (o cursor é capturado quando o navegador permite)
- Segure o botão direito do mouse: mira em primeira pessoa
- Clique esquerdo durante a mira: disparar o Lançador de Petiscos nos objetos do cenário
- `Shift`: Dash Salsicha
- `Espaço`: pular
- `Q`: Super Farejo
- `E`: Latido Sísmico
- `F`: Escavar próximo a círculos de areia
- `U`: melhorias
- `M`: mapa

## Conteúdo do mundo

- Meyui usa o modelo FBX e texturas PBR em `assets/meyui/`.
- O Morro tem plataformas de salto, casas empilhadas, bots de confete e viaturas em patrulha.
- A Melzinha usa o modelo FBX em `assets/melzinha/` e inicia o duelo final com 90 petiscos. O combate tem investidas telegrafadas, recuperação, esquiva com dash e janelas de contra-ataque.
- A trilha procedural e os efeitos sonoros começam após a primeira interação, como exigido pelos navegadores.

O protótipo usa Three.js carregado pelo navegador para renderizar o mundo 3D.
