# Cooperativo nativo · até quatro jogadores

O jogo usa **ENet/UDP real**. O computador que hospeda simula todos os jogadores,
Faro, inimigos, hitboxes, tiros, granadas, drops, compras e o diretor de rounds.
Cada convidado controla um personagem próprio; os outros personagens exibidos
são réplicas de participantes conectados.

## Jogar em duas máquinas

1. Os dois jogadores precisam da mesma versão do projeto/exportação Godot.
2. No **host**, crie ou carregue uma expedição. Pressione **F8**, escolha a porta
   (padrão **27842 UDP**) e clique **HOSPEDAR EXPEDIÇÃO ATUAL**.
3. No **convidado**, ainda no menu inicial, abra **COOPERATIVO · F8**. Informe
   seu nome, o IPv4 do host e a mesma porta; clique **ENTRAR NO HOST**.
4. Em rede doméstica, use o IPv4 da LAN do host. Em locais diferentes, conectem
   primeiro os computadores à mesma rede VPN, como Hamachi ou Radmin, e usem
   o IPv4 que essa VPN atribuiu ao host. O jogo não instala nem configura VPN.

O host precisa permitir o executável do jogo/Godot no firewall da rede utilizada.
Se a conexão falhar, confira IP, porta UDP, firewall e se os computadores estão
na mesma LAN/VPN. `127.0.0.1` serve somente para dois processos na mesma máquina.

Internet pública exige uma rota até o host: VPN ou encaminhamento da porta
**UDP** no roteador. Não há relay, matchmaking, abertura automática de portas
nem garantia de funcionamento atrás de CGNAT. ENet aqui é voltado a sessões
entre pessoas conhecidas; não oferece criptografia de transporte nem contas
online. Referência: [documentação oficial de multiplayer Godot](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#hosting-considerations).

## Regras da sessão

- **1–4 participantes**. Cada adicional acrescenta **80% à vida máxima dos
  inimigos**: 100%, 180%, 260%, 340%. A velocidade não aumenta por causa do
  cooperativo. Entradas e saídas ajustam inimigos existentes preservando a
  porcentagem de vida restante. Dificuldade, rounds e efeitos normais continuam.
- Inventário de quatro slots, mochila, munição, moedas, talentos, perks de
  estações, equipamentos, consumíveis e progressão de **Faro são individuais**.
- Regiões abertas, baús utilizados, desafios, bosses, drops no chão e rounds
  são compartilhados. Um drop é consumido uma vez e pertence a quem o recolhe.
  O jogador que abre um portão paga o custo; todos recebem acesso à região.
- Dano, eliminações e compras são atribuídos ao jogador que os realizou;
  granadas preservam seu dono durante o tempo de detonação. Recompensas de
  conclusão de round/evento/desafio são concedidas a cada carteira conectada;
  o desafio gera somente um conjunto de drops compartilhados.
- **Rounds continuam sem um limite final**, pelo diretor original do host.
  Clientes enviam comandos, nunca valores de dano, moedas ou preço de compra.
- **Esc, inventário, roda de armas e F8 não pausam o mundo online.** O menu
  desativa os controles locais, mas o personagem continua vulnerável. Em solo,
  o comportamento original de pausa continua funcionando.
- Faro tenta sua habilidade de reanimação normalmente. Sem essa habilidade,
  um jogador caído retorna após **10 segundos**, com 60% da vida, perto de um
  parceiro vivo. Se todos caírem, a equipe perde e pode carregar o checkpoint.

## Save, desconexão e retorno

O **host é o dono do save da expedição**. O slot dele guarda o mundo e o estado
individual de todos os convidados conhecidos. Compras, loot e checkpoints
continuam agendando gravações, e o cooperativo também agenda um save a cada
10 segundos. Fechar normalmente ou sair da sessão tenta gravar antes de encerrar.

Cada instalação tem uma identidade aleatória local em `user://coop_identity.cfg`.
O nome exibido pode mudar: a identidade é que permite retomar o mesmo personagem.
Os testes usam identidades e saves isolados em `godot/test-output`.

- Ao desconectar, o personagem e seu Faro deixam o mundo; o host guarda o
  estado deles e recalcula a vida dos inimigos.
- Entrar novamente no **mesmo save do host**, pela mesma instalação, restaura
  inventário, munição restante, moedas, Faro, talentos e perks de área. Um
  convidado que saiu caído volta à regra de retorno em 10 segundos.
- O host pode fechar, reabrir, carregar o slot e hospedar de novo. Os convidados
  recuperam os personagens registrados naquele checkpoint. Até 64 identidades
  são conservadas por expedição; simultaneamente continuam sendo no máximo 4.
- Se o host cair inesperadamente, vale a última gravação concluída. Não há
  migração automática de host nem transferência do save para o convidado.
- Se o host interromper a sessão, convidados voltam ao menu com uma mensagem
  de reconexão. Convidados não sobrescrevem seus slots solo com o save do host.
- Uma nova expedição começa com novos personagens de convidados. Apagar ou
  trocar a identidade local também cria um novo personagem nesse host.

## Validação reproduzível

Em PowerShell, na raiz do repositório:

```powershell
& .\godot\tests\run_coop_test.ps1 -Godot 'C:\caminho\Godot_console.exe'
```

O teste abre **dois processos Godot headless independentes** em loopback, com
servidor e cliente ENet reais, e usa porta de teste 27943. `-Port` altera essa
porta. Cada processo tem watchdog e encerra sozinho; o teste não encerra outras
instâncias do jogo. Logs e resultados JSON ficam em `godot/test-output/coop_*`.

Os asserts cobrem conexão, movimento no host, hitbox/tiro/dano/munição, vida
1,8× sem aumento de velocidade, moeda coletada uma vez, compras individuais,
Faro, estação de perk acessada por E, portão compartilhado, arma coletada por E,
granada real e atribuição de dano, recompensa de round, vulnerabilidade durante
pausa, gravação, recarga do checkpoint e reconexão com a mesma progressão.

A validação automatizada exercita dois participantes locais. A capacidade de
quatro é limitada no servidor; latência, firewall, VPN e conexão entre máquinas
remotas precisam ser avaliados na rede onde vocês vão jogar. O protocolo envia
comandos a 30 Hz e snapshots a 10 Hz, comprimidos com FastLZ, com previsão do movimento local e
interpolação dos demais personagens. Sob latência/perda altas, correções e
atraso na confirmação de tiros/compras podem ficar perceptíveis.
