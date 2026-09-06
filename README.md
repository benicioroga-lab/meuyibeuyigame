# Meyui Beuyi · Morro do Vento

A versão atual do jogo é nativa em **Godot 4.7.2 Standard**, na pasta [`godot/`](godot/). Esta branch `v2` reúne combate, loot, rounds, exploração, Faro, menus e saves. O protótipo para navegador também permanece neste repositório.

## Tutorial: rodar a versão Godot

### 1. Preparar

- Tenha o Git e a Godot **4.7.2 Standard** extraída no computador. A edição .NET não é necessária.
- Não é preciso instalar Node.js, npm, plugins ou pacotes para jogar a versão nativa.

No PowerShell, clone a branch de desenvolvimento:

```powershell
git clone --branch v2 --single-branch https://github.com/benicioroga-lab/meuyibeuyigame.git
cd meuyibeuyigame
```

Se já possui o repositório, use `git fetch origin` e `git switch v2` com seu trabalho local salvo antes de trocar de branch.

### 2. Abrir pelo editor

1. Abra o executável da Godot.
2. No gerenciador de projetos, clique em **Importar** e selecione `godot/project.godot`.
3. Aguarde a importação e abra o projeto.
4. Pressione **F5** para executar o jogo. No menu, escolha **Nova expedição**, dificuldade e um slot, ou **Continuar** para retomar um save.

O mapa e as interfaces são construídos durante a execução; a cena no editor não mostra o mundo pronto. Use **F5** para visualizar o resultado.

### 3. Abrir diretamente no Windows

Na raiz do repositório:

```powershell
.\godot\open.ps1 -Play
```

O script procura a Godot extraída em `Downloads`. Se estiver em outro local, informe o arquivo executável:

```powershell
.\godot\open.ps1 -GodotExe "C:\Godot\Godot_v4.7.2-stable_win64.exe" -Play
```

Se o PowerShell bloquear scripts, importe o projeto pelo editor ou execute a engine diretamente, sem mudar políticas da máquina:

```powershell
& "C:\Godot\Godot_v4.7.2-stable_win64.exe" --path .\godot
```

### 4. Jogar e atualizar

| Entrada | Ação na versão Godot |
| --- | --- |
| WASD / mouse | Mover / olhar |
| Esquerdo / direito | Atirar / mirar |
| R | Recarregar |
| Espaço / Shift | Pular / esquiva e corrida |
| E | Recolher loot e interagir com portas/estações |
| Tab / I | Bancada de melhorias / inventário |
| C | Faro: caçar / acompanhar |
| F1 | Alternar primeira e terceira pessoa |
| L / V | Lanterna / inspecionar arma |
| Esc | Pausar e abrir configurações |

Depois de atualizar o código, pare a execução e pressione **F5** novamente. Os saves ficam fora do repositório, em `%APPDATA%\Godot\app_userdata\Meyui Beuyi · Morro do Vento\`, com três slots, backups e preferências separadas. Os saves do navegador pertencem ao protótipo web.

Se o jogo estiver pesado, selecione **Configurações → Imagem → Baixo**. O campo de visão fica em **Controles** e pode ser ajustado durante a pausa.

Veja o [guia completo da versão Godot](godot/README.md) para arquitetura, sistemas e comandos dos testes.

### Explorar o mapa ampliado

No Pátio do Farol, siga a placa **Jardim** e use **E** no portão (120 petiscos, round 1). O **Jardim das Nascentes** tem árvores, fonte, estufa com baú, quiosque e um desafio de defesa. Pelo jardim, entre no **Shopping Aurora** (320, round 2), com lojas acessíveis, café, arsenal, oficina e mezanino com duas escadas. O **Cine Última Luz** (480, round 3) conecta o shopping à antiga Oficina Suspensa: explore bilheteria, plateia, palco e arquivo do projecionista.

As nove regiões formam circuitos de exploração; os portões funcionam pelos dois lados. Saves anteriores continuam válidos e passam a oferecer os novos acessos. O mapa ampliado pertence à versão **Godot**.

## Protótipo web

Survival/looter shooter solo para navegador. Meyui e Faro enfrentam a **Liga do Ruído**, uma facção fictícia, no Morro do Vento. O bairro tem inspiração arquitetônica brasileira; moradores comuns não são apresentados como inimigos.

### Executar no navegador

```powershell
npm install
npm start
```

Abra http://127.0.0.1:8000/. Alterações no código durante uma partida mostram um botão para reiniciar e aplicar a atualização. Menus, perda de foco e troca de aba pausam a simulação.

```powershell
npm test
```

## Controles

| Entrada | Ação |
|---|---|
| WASD / setas | Mover na direção da câmera |
| Mouse | Olhar livremente |
| Esquerdo / direito | Atirar / mirar simultaneamente |
| R | Recarregar; trocar de arma cancela |
| Roda / 1–7 | Trocar equipamento |
| Tab / U / I | Melhorias / melhorias / mochila |
| V | Inspecionar a arma |
| F | Interagir com loot, baús, portas e estações |
| Espaço / Shift | Pular / esquivar |
| E / Q | Latido sísmico / farejar um objetivo |
| C | Faro: caçar / acompanhar |
| F1 | Primeira pessoa / terceira pessoa |
| M / J | Mapa / desafios |
| Esc / P | Pausar, fechar menus e liberar o cursor |

Primeira pessoa é o padrão. A arma fica oculta na terceira pessoa. Nos navegadores sem captura do mouse, sair da área do jogo pausa. Há controles de toque.

## Ciclo da expedição

Escolha uma entre cinco dificuldades e, opcionalmente, Chaos. O menu compara risco e recompensa. Chaos I começa disponível; fragmentos liberam os níveis seguintes até V.

Abra o baú inicial, sobreviva e explore três patamares, ruas, becos, escadas, rampas, interiores, telhados e uma galeria subterrânea. As rotas principais são fixas; caixas e detalhes variam por seed. Portas pagas abrem atalhos reais.

A cada três rounds, escolha uma entre três melhorias para formar uma build. Crítico, perfuração, explosões de headshot, devolução de munição, regeneração e Faro combinam entre si. Dinheiro de eliminações aparece no chão; XP entra imediatamente.

As Boss Zones da Cisterna e do Pátio das Antenas guardam O Regente e Fornalha. Cada um tem três fases, ataques anunciados e portões. A vitória rende arma lendária, peça rara, dinheiro e fragmentos. Arenas ficam disponíveis novamente após dez rounds. Invasões podem trazer bosses em áreas abertas.

## Progressão contínua

Dez armas base geram instâncias com atributos, fabricantes, raridade e peças próprias. As seis raridades têm nome, símbolo e cor. Perks lendários mudam a mecânica: quinto tiro elétrico, última bala reforçada, explosão de headshot, cadência por eliminações e disparo extra.

O inventário guarda 16 armas e 40 peças. Compare, equipe, favorite ou recicle. Peças podem ser encontradas, compradas, retiradas e instaladas em outra arma. Ópticas ampliam ADS; receptores de rajada, munição alternada e canos elementais alteram disparos reais.

**A Forja V não é o fim da progressão.** Depois dela, o aperfeiçoamento continua sem último nível, acrescentando dano e repondo munição. A interface mostra o próximo ganho e custo. Ganhos seguem curva logarítmica; custos crescem. Rerolls e novas combinações de loot oferecem alternativas. Uma arma favorita pode continuar recebendo investimento.

Pente e reserva são finitos. Recarga vazia demora mais que a tática; munição só é transferida ao concluir. O power-up temporário de munição infinita é a exceção explícita. Recarga por eliminação transfere balas da reserva.

## Desafio, Faro e legado

Comuns, runners, tanques, brutes, exploders, atiradores, shields, berserkers, assassins e supports compõem as hordas. Elites têm modificadores elementais, frenéticos, vampíricos ou explosivos. Acertos usam partes articuladas dos modelos; escudos frontais podem ser quebrados ou flanqueados.

Velocidades têm limites por classe. Rounds altos usam formações, especiais e modificadores. HP dos comuns permanece limitado. O diretor considera saúde, munição, eficiência e inimigos vivos para alternar pressão e intervalos curtos. Não há limite de rounds.

Faro tem treino de combate e árvores de apoio/sobrevivência: coleta, marcação, escudo, distração e resgate. Equipamento, coleira e efeitos acompanham sua evolução. O resgate exige que ele chegue até Meyui.

Drops temporários oferecem munição infinita, dano dobrado, frenesi, pulso em área, magnetismo, bolada e sobrecarga elemental. Eventos incluem apagão, Lua de Ferrugem, invasão de elites, loot dobrado, desconto do armeiro e caça ao boss. Há entrega opcional e desafios locais.

Fragmentos permanentes vêm de bosses, desafios, conquistas e marcos de rounds. Liberam opções iniciais, peças, especializações, skins e Chaos; bônus diretos de preparação são pequenos e limitados. Save validado e migrável usa apenas a chave deste jogo no navegador, com prevenção de recompensas duplicadas.

## Arquitetura

Todos os módulos abaixo ficam em `systems/`:

| Sistemas | Responsabilidade |
|---|---|
| run-config, run-director | Dificuldade, rounds, perks, eventos e ritmo |
| loot-config, weapon-rolls, arsenal | Catálogos, rolls, munição, inventário e forja |
| hit-detection, combat, combat-effects | Hitscan, cobertura, dano, elementos e animações |
| enemy-config, enemies, enemy-projectiles | Classes, animação, IA e disparos |
| bosses | Arenas, fases, ataques e recompensas |
| hill-world, navigation, player-movement | Mundo, alturas, colisão e rotas |
| loot-world, shop | Drops, comparação e compras |
| meta-progression, dog | Legado, conquistas e Faro |
| run-ui, minimap | Menu, builds e mapa fixo |
| audio | Música original adaptativa e efeitos em camadas |

`app.js` integra os sistemas; `experience.js` cuida da entrada, câmeras, pausa e HUD. Testes exercitam munição, cobertura, dano, dois botões do mouse, economia, refinamento contínuo, bosses, navegação vertical, persistência e simulação prolongada. Recursos transitórios têm limites e descarte. Arquitetura estática usa instâncias por material.

Three.js carrega pelo CDN na mesma versão dos testes. Meyui mantém seu modelo em `assets/meyui/`; inimigos, bosses e mundo são construídos em código. Música e efeitos originais usam Web Audio e começam após interação. Sensibilidade, mixagem, números de dano e redução de movimento são configuráveis.
