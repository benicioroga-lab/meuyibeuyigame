# Meyui Beuyi: Caos no Rio

Protótipo 3D de aventura cartunesca no navegador: explore uma cidade costeira fictícia, colete petiscos, provoque caos inofensivo e compre melhorias para o Meyui Beuyi.

## Rodar localmente

```powershell
npm start
```

Abra `http://127.0.0.1:8000`.

## Controles

- `WASD` ou setas: andar na direção da câmera
- Mova o mouse: girar a câmera, sem segurar botão. Ao iniciar, o jogo solicita captura do cursor.
- Primeira pessoa é a câmera padrão. `F1` alterna para terceira pessoa e volta; a arma só aparece em primeira pessoa.
- Segure o botão direito do mouse: aproximar a mira. O esquerdo funciona simultaneamente.
- Clique ou segure o botão esquerdo: disparar na mira central, respeitando cadência e munição.
- `R`: recarregar; trocar de arma cancela a recarga sem transferir munição.
- Roda do mouse / `1` a `7`: equipar armas compradas.
- `C`: alternar Faro entre caçar e acompanhar.
- `Shift`: Dash Salsicha
- `Espaço`: pular
- `Q`: Super Farejo
- `E`: Latido Sísmico
- `F`: Escavar próximo a círculos de areia
- `Tab`: abrir melhorias (`U` também funciona); `Esc` fecha. Dentro dos menus, Tab navega entre os controles.
- `M`: mapa
- `G`: formar gangue com um cachorro próximo
- `J`: missões
- `H`: controles
- `Esc` ou `P`: pausar e liberar o mouse. Clique em **Continuar** para recapturá-lo.

Todos os menus pausam movimento, inimigos, rounds e recargas. Trocar de aba ou perder o foco também pausa. Nos navegadores que não permitem Pointer Lock, o mouse gira a visão livremente dentro da página; sair dela pausa a partida.

## Interface e rounds

- Round, inimigos restantes e intervalo entre ondas no alto à esquerda.
- Saldo de petiscos à esquerda, com ganhos flutuantes e contador separado de itens encontrados. O saldo é usado na loja.
- Retrato do modelo de Meyui, vida segmentada e experiência no rodapé esquerdo.
- Emblemas das melhorias efetivamente compradas no centro inferior, com nível e acesso à loja.
- Arma, pente / reserva e progresso de recarga no rodapé direito; estado e vida do Faro à esquerda.
- Minimapa permanentemente no HUD, norte fixo, alcance inicial de 32 m e zoom de 18 a 60 m. `M` abre o mapa maior com nomes das áreas.
- Primeiro round após 8 segundos. Ondas concluídas dão petiscos, até 20 de vida, recuperação do Faro e caixas de munição, seguidas de 12 segundos para se preparar. Cada quinto round traz o Rei da Sucata.
- Ao ficar sem vida, a tela de resultado mostra round, ganhos e duração. Nova aventura retorna ao menu com uma partida limpa.
- Sensibilidade, volume geral, música, efeitos, distância da terceira pessoa, inversão vertical e redução de movimento são ajustáveis e salvos localmente. O progresso da partida fica em memória.

## Arsenal e progressão

| Arma | Round | Preço | Pente / reserva inicial | Identidade |
|---|---:|---:|---:|---|
| Biscoiteira 12 | 1 | inicial | 12 / 84 | Pistola precisa |
| Calçadão | 2 | 420 | 18 / 126 | Carabina rápida |
| Marreta | 4 | 950 | 6 / 42 | Dano alto e perfuração |
| Pipoqueira | 6 | 1.350 | 36 / 216 | Automática com dispersão |
| Brasa | 8 | 2.000 | 24 / 144 | Dano incendiário contínuo |
| Voltagem | 10 | 3.000 | 16 / 96 | Choque entre alvos próximos |
| Zero Grau | 12 | 4.000 | 10 / 60 | Impacto em área e lentidão |

Cada arma guarda munição e melhorias próprias. A loja compara dano, capacidade e recarga atuais com o próximo nível. As reservas são finitas: recolha caixas ou reponha na loja. Tiros são hitscan; rastros são visuais, sem atraso na aplicação de dano. Corpos articulados fornecem as superfícies de acerto, cabeça causa crítico e a trajetória respeita cobertura tanto da câmera quanto da boca da arma.

Faro possui melhorias de dano, frequência, velocidade, vida, resistência, crítico, múltiplos alvos e três estágios elementais. Coleira, aura e efeitos acompanham sua evolução. Ao cair, ele se recupera após nove segundos; a loja também oferece tratamento.

Inimigos têm silhuetas, camisas de futebol fictícias, tons de pele marrom, rádios, chinelos e variações de cabelo, incluindo platinado. Corredores, tanques, atiradores e chefes complementam os inimigos básicos. Velocidade e HP têm limites explícitos: a dificuldade posterior usa composição e quantidade, com até 31 inimigos por onda.

## Organização dos sistemas

- `systems/config.js`: armas, variantes de inimigos, Faro, custos e curvas de rounds.
- `systems/arsenal.js`: inventário, cadência, munição e recarga sem dependência de renderização.
- `systems/hit-detection.js` e `systems/combat.js`: raycasts, cobertura, dano e efeitos elementais.
- `systems/enemies.js`, `systems/navigation.js` e `systems/dog.js`: modelos articulados, perseguição por rotas e evolução do companheiro.
- `systems/combat-effects.js`: arma, recoil, rastros, números de dano e efeitos com limites e descarte.
- `systems/shop.js`: compras com comparações atual → próximo.
- `systems/world-detail.js` e `systems/minimap.js`: microáreas e mapa com norte fixo.
- `systems/audio.js`: trilha original adaptativa, disparos em camadas, percussão, baixo, harmonia, reverberação curta e mixagem com volumes separados. Não depende de downloads para tocar.
- `experience.js`: entrada, câmeras, menus, HUD e acessibilidade.

## Verificação

```powershell
npm install
npm test
```

Os testes cobrem dano imediato, geometria animada, cobertura da câmera e da arma, perfuração, efeitos elementais, recarga parcial, cancelamento, pausa, compras, recuperação do Faro, velocidade máxima, colisões e o uso simultâneo dos dois botões do mouse. Uma simulação de cinco minutos percorre as sete armas e verifica limites de munição, atores e efeitos. A dependência de desenvolvimento Three.js fornece a mesma geometria usada pelo jogo; o navegador continua carregando a versão existente pelo CDN.

## Conteúdo do mundo

- Meyui usa o modelo FBX e texturas PBR em `assets/meyui/`.
- Praça com fonte, mercado, garagem, jardim de ipês, quadra e viela complementam praia e morro. Detalhes e áreas externas variam entre partidas.
- O Morro tem plataformas de salto, casas empilhadas e viaturas em patrulha.
- A Melzinha usa o modelo FBX em `assets/melzinha/` e inicia o duelo final com 90 petiscos. O combate tem investidas telegrafadas, recuperação, esquiva com dash e janelas de contra-ataque.
- A trilha e os efeitos sonoros começam após a primeira interação, como exigido pelos navegadores; a música acompanha a pressão da horda e silencia nos menus.

O protótipo usa Three.js carregado pelo navegador para renderizar o mundo 3D.
