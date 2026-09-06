# Meyui Beuyi · Morro do Vento

Survival/looter de rounds em **Godot 4.7.2 Standard**, com GDScript e renderizador **Compatibility**. Esta versão jogável nativa conecta combate, exploração, loot, builds e continuidade de partida. Modelos, animações, cenário e áudio são originais e procedurais; ainda precisam de iterações artísticas e de balanceamento. Não requer .NET, addons ou downloads de assets.

## Abrir e jogar

Importe `project.godot` na Godot e pressione **F5**. A cena principal é `scenes/main.tscn`; com ela aberta, **F6** também funciona. O cenário e as interfaces são construídos em código durante a execução.

No PowerShell, dentro desta pasta:

```powershell
.\open.ps1         # Abre o editor; procura a Godot extraída em Downloads.
.\open.ps1 -Play   # Abre o jogo diretamente.
.\open.ps1 -GodotExe "C:\Godot\Godot.exe" -Play
```

No menu, escolha dificuldade, Indutor de Caos e um dos três slots. Uma nova run começa no Pátio do Farol, com a Biscoiteira e Faro. Colete os primeiros espólios, use **Tab** para a forja e **E** nos baús e acessos. Abrir novas regiões oferece rotas, recursos, desafios e uma zona de boss.

Os portões podem ser comprados **pelos dois lados**, inclusive se você estiver dentro de uma região ainda bloqueada. O custo e o round exigidos são os mesmos. Grades bloqueiam personagens e golpes corpo a corpo, mas permitem tiros; paredes continuam bloqueando disparos. O fechamento temporário da arena de boss permanece ativo durante a luta.

| Comando | Ação |
| --- | --- |
| WASD / mouse | Mover / olhar |
| Botão esquerdo / direito | Atirar / mirar |
| R | Recarregar; pente vazio inicia recarga se houver reserva |
| Shift / Espaço | Esquiva curta seguida de corrida / salto |
| 1–4 | Selecionar um dos quatro slots equipados |
| Segurar T | Roda de armas; solte para equipar a seleção |
| Ctrl / Z | Agachar / mergulhar com impulso e intervalo de recuperação |
| I | Abrir inventário e escolher qualquer arma da mochila |
| Tab | Abrir/fechar a forja e menus de melhoria |
| E | Interagir com loot, baús, comerciantes, portas e eventos próximos |
| F, mirando uma arma | Trocar com a arma na mão; a anterior fica no chão |
| G / H / J | Usar granada / kit de cura / caixa de munição |
| C | Alternar Faro entre caçar e acompanhar |
| L / V | Lanterna / inspecionar arma |
| F1 | Alternar primeira e terceira pessoa |
| Esc | Pausar/continuar em solo; online, o mundo continua |
| F8 | Hospedar ou entrar no cooperativo |

## Sistemas disponíveis

- **Combate:** munição individual por arma, recargas tática e vazia, categorias com cadências e animações próprias, ADS, recuo, estojos ejetados e impactos. O tiro parte da mira central e verifica obstruções do cano. Cabeça, torso e pernas respondem de forma diferente; críticos, elementos, abates e rounds têm feedback audiovisual.
- **Loot e armas:** 13 modelos, incluindo três lendárias exclusivas, 6 raridades, 7 fabricantes fictícios, rolls por instância e 20 modificadores comportamentais. Attachments ocupam cinco slots: mira, cano, underbarrel, pente e internos; as peças também aparecem nas prévias e no equipamento. Quatro slots de arma, um de granada e um de modificador complementam a mochila com favoritos/lixo, comparação, ordenação, autoequipar, venda e desmontagem.
- **Build e economia:** 12 perks e refinamento de armas sem teto fixo de compras, além de rerolls de atributo, elemento, modificador, attachment e fabricante. Custos aumentam; velocidade e resistência têm retornos decrescentes. Petiscos financiam a run; materiais vêm da desmontagem. Sigilos, registros e especializações de Faro persistem no perfil.
- **Faro:** quatro especializações — combatente, coletor, apoio e guardião — e oito ramos: ataque, sobrevivência, loot, apoio, elemental, controle, abastecimento e vínculo. Fogo/choque/gelo selecionáveis, ataques em grupo, controle, cura por mordida e busca de munição dependem da build. Equipamento, coleira e proteção evoluem visualmente. Compras continuam além dos níveis iniciais, com limites de velocidade/cadência.
- **Mundo:** onze regiões conectadas, entre −4 m e +8 m: Pátio do Farol, Beco das Marés, Oficina Suspensa, Galeria da Chuva, Lajes do Sinal, Quadra do Eco, Jardim das Nascentes, Shopping Aurora, Cine Última Luz, Casa das Bombas e Terminal da Madrugada. Fachadas com janelas profundas, cisternas, tubulações e ar-condicionado; reservatórios curvos, bondes, interiores, escadas e rotas alternativas. Navegação e colisão são nativas.
- **Hordas:** 11 arquétipos comuns/especiais, 3 modificadores de elite e 3 bosses com padrões distintos. A facção hostil é a fictícia **Liga do Ruído**. Rounds seguem sem um final programado, com composição progressiva, cinco dificuldades e Caos. O diretor limita a 24 inimigos simultâneos, dosa os spawns conforme recursos/pressão e oferece pausas de 8–12 segundos entre rounds.
- **Eventos:** apagão, tempestade, invasão de elites, loot dobrado, suprimentos e caçada de boss. Sete power-ups temporários/imediatos complementam as recompensas da exploração e dos desafios.
- **Interface:** personagem à esquerda, loadout central e mochila à direita, com abas superiores e miniaturas 3D. Bancada, utilitários, talentos e Faro têm páginas próprias. HUD com painéis opacos compactos, texto claro, munição em destaque, petiscos separados da vida e atalhos de consumíveis. Atributos avançados aparecem sob demanda.
- **Cooperativo:** ENet para 2–4 pessoas por IP/LAN/VPN, com host autoritativo, mundo compartilhado e personagens individuais. Cada jogador adicional acrescenta 80% ao HP dos inimigos. Checkpoint e reconexão preservam as builds. Consulte [o guia de multiplayer](README_MULTIPLAYER.md).

O Batedor começa com **22 de dano**: sem defesa, cinco golpes derrubam o jogador de 100 HP. Todo golpe de inimigo não boss recebe um teto de **40% da vida máxima**, aplicado antes da armadura e da proteção de Faro; essas melhorias continuam úteis em rounds altos. Arcos vermelhos indicam a origem dos ataques, com vinheta e aviso de vida crítica. Absorção total pelo escudo tem feedback distinto. A retaliação às mordidas de Faro tem duração e intervalo limitados, preservando a provocação própria da especialização guardião.

No chão, munição aparece como caixa com cartuchos e armas têm silhuetas próprias por família. Aponte a mira para ver raridade, nível, fabricante, comparação e modificadores. **E** guarda a arma; **F** troca pela equipada, deixando a anterior no chão. Favoritos são protegidos e uma mochila cheia não perde itens na troca.

Abates normais têm 10% de chance base de arma; elites, 35%. Lendárias e míticas são muito menos frequentes que as demais; chefes preservam suas recompensas especiais. Itens comuns têm sinal discreto; lendários/míticos usam feixes maiores, brilho e sons originais distintos. Portas, descarte de armas, passos, corrida, mergulho e fases da recarga também têm cues próprios.

As lendárias **Maré de Íons** (round 7), **Último Fotograma** (8) e **Expresso 02:17** (9) têm corpos, sons e assinaturas próprios: corrente elétrica, explosões críticas e cadência por eliminações. Elas entram no loot lendário/mítico, com rolls e attachments, e não são vendidas no catálogo comum. Kits, munição e três tipos de granada usam estoques finitos na página **Utilitários**.

## Jardim, shopping e cinema

O circuito sai pelo portão ao sul do Pátio do Farol. Placas levam ao jardim, shopping e cinema, com retorno à Oficina Suspensa por uma escada de serviço. Pelo jardim, duas escadas descem até a Casa das Bombas; duas passagens ao sul do shopping chegam ao terminal. Cada destino tem loot, um desafio ou serviço e caminhos de saída.

| Região | Acesso | Exploração e utilidade |
| --- | --- | --- |
| Jardim das Nascentes | 120 petiscos · round 1 | Caminhos entre árvores, fonte, bancos, estufa envidraçada com baú, quiosque de compras e desafio **Defender a nascente**: 10 eliminações locais em 80 s. |
| Shopping Aurora | 320 petiscos · round 2 | Átrio com cobertura, farmácia com estoque, arsenal, café com reserva, oficina de upgrades e cofre no mezanino. Duas escadas permitem circular entre os pisos por caminhos diferentes. |
| Cine Última Luz | 480 petiscos · round 3 | Bilheteria com caixa, bomboniere, sala com poltronas e corredores laterais, palco acessível e arquivo com loot. Desafio **Última sessão**: 16 eliminações locais em 90 s. Saída de serviço para a oficina. |
| Casa das Bombas | 360 petiscos · round 3 | Reservatórios, tubulações e armário de manutenção. **Restabelecer a pressão**: acumule 35 segundos perto do painel, mantendo inimigos afastados, em até 85 s. |
| Terminal da Madrugada | 600 petiscos · round 5 | Bondes, cobertura, trilhos e despacho com cofre. **Último embarque**: 18 eliminações no terminal em 100 s, com pressão adicional de inimigos. |

Desafios pagam petiscos e equipamento épico e reabrem após quatro rounds; baús e reservas, após cinco. A compra de uma região abre seus acessos correspondentes pelos dois lados. Novas regiões começam fechadas em saves antigos, preservando compras anteriores.

Cada região possui uma **estação exclusiva de perks**, compráveis apenas por proximidade com **E**. O painel mostra ganho atual → próximo e custo crescente. Pátio: resistência; mercado: reserva; oficina: recarga; galeria: regeneração; lajes: dano crítico; quadra: dano; jardim: dano de Faro; shopping: fortuna; cinema: chance crítica; bombas: vida; terminal: movimento. São bônus adicionais aos talentos do menu, com retornos decrescentes e persistência no save individual.

Inimigos priorizam spawns próximos dentro do distrito do jogador. As hordas usam criaturas com silhuetas de rastejadores, carapaças e espectros, membros articulados e olhos luminosos com oclusão; humanos ficam restritos aos chefes da facção. Jogador, Faro e inimigos usam as mesmas escadas. Chuva fica acima das coberturas; opções de vegetação controlam folhas e grama sem remover troncos sólidos.

A noite tem luz ambiente reduzida, oclusão ambiente e sombras locais limitadas por qualidade/distância. Occluders acompanham paredes e volumes sólidos, deixando portas abertas livres. No apagão, luzes urbanas apagam e a lanterna passa a ser essencial; olhos e loot mantêm pontos de referência. A interface permanece nítida e independente da iluminação 3D.

## Saves e configurações

Há **três slots de partida**. O autosave é agendado em compras e momentos de progressão, incluindo fim de round; os menus também permitem salvar/carregar. Inventário, munição, build, Faro, regiões, diretor, inimigos vivos, loot e estado de combate entram no snapshot. Perfil e preferências são separados da run.

Os arquivos usam JSON versionado, verificação de integridade, gravação temporária e backup do último save válido. Ao encontrar um arquivo principal danificado, o carregamento tenta recuperar o backup; dados inválidos são rejeitados antes de substituir a partida ativa.

No Windows, a pasta desta instalação é:

```text
%APPDATA%\Godot\app_userdata\Meyui Beuyi · Morro do Vento\
  saves\slot_1.json        # Também slot_2/slot_3; backups terminam em .bak.
  profile\slot_1.json      # Sigilos, recorde, registros e desbloqueios.
  settings\preferences.json
```

As opções alteram recursos usados pelo Compatibility: resolução/modo de janela, FPS/VSync, sombras, distância, chuva/partículas, vegetação, MSAA, neblina e filtragem. Também há FOV, sensibilidades, balanço/recuo visual, flashes reduzidos, escala/contraste/paleta da UI e volumes separados. O preset Ultra ajusta esses recursos; não adiciona ray tracing ou renderização fotorealista.

Os ajustes são aplicados e salvos imediatamente, incluindo FOV durante a pausa. Em tela cheia e sem bordas, a resolução controla o tamanho de renderização 3D mantendo a proporção do monitor e a interface nítida. Em janela, controla o tamanho da janela; mudar outro ajuste preserva redimensionamentos manuais. Qualidade também alcança as prévias 3D da bancada e do cachorro.

## Organização e validação

`data/` contém armas, loot, inimigos e evolução de Faro. `main.gd` coordena transações e a run; `inventory.gd` guarda as instâncias; `run_director.gd` controla hordas/eventos; `run_progression.gd` calcula perks. `world.gd`, `world_expansion.gd` e `exploration.gd` cuidam das regiões/interações. A expansão registra regiões, serviços, spawns e portões na mesma estrutura do mundo; o validador de save reutiliza seus identificadores. `player.gd`, `enemy.gd` e `companion.gd` executam o combate. Save, validação, opções, áudio e interfaces possuem scripts próprios.

Execute na pasta `godot`, informando o executável **console** da instalação:

```powershell
$GodotExe = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$tests = @('loot', 'loot_visuals', 'progression', 'director', 'weapons', 'actors', 'world', 'map_expansion', 'destinations', 'exploration', 'equipment_revision', 'save', 'settings', 'settings_ui', 'expedition', 'ui', 'stress')
foreach ($test in $tests) {
	& $GodotExe --headless --path . --script "res://tests/test_$test.gd"
	if ($LASTEXITCODE -ne 0) { throw "Falha: $test" }
}
```

Esses testes cobrem modelos/rolls, conservação de munição, attachments/rerolls, efeitos de combate, navegação, Faro, progressão prolongada, recuperação de saves, configurações e integração da expedição/UI. `test_run.gd` é um alias de `test_expedition.gd`. `render_showcase.gd`, executado **sem `--headless`**, produz capturas para revisão visual em `test-output/`; testes automatizados não substituem jogar e avaliar ritmo, legibilidade e som.

`test_settings_ui.gd -- --capture`, sem `--headless`, exercita os controles com a GPU e registra FOV/qualidade em `test-output/settings-regression/`. `render_combat_feedback.gd` registra fichas de loot e dano sofrido em `test-output/combat-feedback/`; acrescente `-- --large-ui` para repetir com interface em 1,3×. Todos usam saves e preferências de teste isolados.

`test_world.gd` valida os destinos, pisos, portas nos dois sentidos e integridade da malha de navegação. `test_map_expansion.gd` percorre fisicamente os interiores com os controles do jogador e verifica saves novos/antigos. `test_stress.gd` também faz Faro e inimigos subirem/descerem as novas escadas. Para gerar oito capturas da expansão com a GPU:

```powershell
& $GodotExe --path . --script res://tests/render_map_expansion.gd
```

As imagens ficam em `test-output/map-expansion/`.

`.godot/` e `test-output/` são caches/artefatos locais ignorados pelo Git. O protótipo web permanece na raiz do repositório; este projeto nativo tem sua própria execução e seus próprios saves.

`test_destinations.gd` percorre fisicamente as duas novas regiões, compra seus perks por E e verifica desafios e saves. `render_hud_revision.gd` captura o HUD normal, dano e recarga; `-- --large-ui` testa escala 1,3×. `render_destinations.gd` captura mapa e lendárias; `render_equipment_revision.gd` registra inventário/bancada/Faro. Para validar rede, use `tests/run_coop_test.ps1`, que abre dois processos ENet reais e salva os resultados em `test-output/coop_*`.
