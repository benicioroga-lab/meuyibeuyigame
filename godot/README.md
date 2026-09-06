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
| 1, 2, 3 | Equipar uma das três primeiras armas da mochila |
| I | Abrir inventário e escolher qualquer arma da mochila |
| Tab | Abrir/fechar a forja e menus de melhoria |
| E | Interagir com loot, baús, comerciantes, portas e eventos próximos |
| C | Alternar Faro entre caçar e acompanhar |
| L / V | Lanterna / inspecionar arma |
| F1 | Alternar primeira e terceira pessoa |
| Esc | Pausar/continuar; menus de equipamento também pausam a run |

## Sistemas disponíveis

- **Combate:** munição individual por arma, recargas tática e vazia, categorias com cadências e animações próprias, ADS, recuo, estojos ejetados e impactos. O tiro parte da mira central e verifica obstruções do cano. Cabeça, torso e pernas respondem de forma diferente; críticos, elementos, abates e rounds têm feedback audiovisual.
- **Loot e armas:** 10 modelos em 10 famílias, 6 raridades, 7 fabricantes fictícios, rolls por instância e 20 modificadores comportamentais. As 20 peças de attachment ocupam cinco slots: mira, cano, underbarrel, pente e internos. Comparação contextual no chão, mochila com favoritos/lixo, ordenação, autoequipar, venda e desmontagem.
- **Build e economia:** 12 perks e refinamento de armas sem teto fixo de compras, além de rerolls de atributo, elemento, modificador, attachment e fabricante. Custos aumentam; velocidade e resistência têm retornos decrescentes. Petiscos financiam a run; materiais vêm da desmontagem. Sigilos, registros e especializações de Faro persistem no perfil.
- **Faro:** quatro especializações — combatente, coletor, apoio e guardião — e quatro ramos de evolução: ataque, sobrevivência, loot e apoio. Compras continuam além dos níveis iniciais, com limites de velocidade/cadência para preservar o combate. Equipamento visual acompanha a evolução; coleta, cura, escudo e resgate dependem da build.
- **Mundo:** seis regiões conectadas, entre o subterrâneo a −4 m e as lajes a +8 m: Pátio do Farol, Beco das Marés, Oficina Suspensa, Galeria da Chuva, Lajes do Sinal e Quadra do Eco. Noite, chuva, neblina e luzes urbanas, com interiores, escadas, rampas, portões compráveis, baús, reservas escondidas, comerciantes e desafios. A navegação usa a física e o NavigationServer3D da Godot.
- **Hordas:** 11 arquétipos comuns/especiais, 3 modificadores de elite e 3 bosses com padrões distintos. A facção hostil é a fictícia **Liga do Ruído**. Rounds seguem sem um final programado, com composição progressiva, cinco dificuldades e Caos. O diretor limita a 24 inimigos simultâneos, dosa os spawns conforme recursos/pressão e oferece pausas de 8–12 segundos entre rounds.
- **Eventos:** apagão, tempestade, invasão de elites, loot dobrado, suprimentos e caçada de boss. Sete power-ups temporários/imediatos complementam as recompensas da exploração e dos desafios.
- **Interface:** menu principal, continuação, slots, configurações, extras, HUD contextual e bancada com previews de arma/Faro. Atributos avançados aparecem sob demanda, com ícones e comparação atual → próxima.

O Batedor começa com **22 de dano**: sem defesa, cinco golpes derrubam o jogador de 100 HP. Todo golpe de inimigo não boss recebe um teto de **40% da vida máxima**, aplicado antes da armadura e da proteção de Faro; essas melhorias continuam úteis em rounds altos. Arcos vermelhos indicam a origem dos ataques, com vinheta e aviso de vida crítica. Absorção total pelo escudo tem feedback distinto. A retaliação às mordidas de Faro tem duração e intervalo limitados, preservando a provocação própria da especialização guardião.

No chão, munição aparece como caixa com cartuchos e armas têm silhuetas próprias por família. Aponte a mira para destacar o item e ver sua ficha: raridade, nível, fabricante, comparação de atributos e modificadores. A seleção acompanha a mira entre drops próximos; recolher usa **E**, exige proximidade e respeita obstáculos.

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

`data/` contém armas, loot, inimigos e evolução de Faro. `main.gd` coordena transações e a run; `inventory.gd` guarda as instâncias; `run_director.gd` controla hordas/eventos; `run_progression.gd` calcula perks. `world.gd` e `exploration.gd` cuidam das regiões/interações. `player.gd`, `enemy.gd` e `companion.gd` executam o combate. Save, validação, opções, áudio e interfaces possuem scripts próprios.

Execute na pasta `godot`, informando o executável **console** da instalação:

```powershell
$GodotExe = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$tests = @('loot', 'loot_visuals', 'progression', 'director', 'weapons', 'actors', 'world', 'exploration', 'save', 'settings', 'settings_ui', 'expedition', 'ui', 'stress')
foreach ($test in $tests) {
	& $GodotExe --headless --path . --script "res://tests/test_$test.gd"
	if ($LASTEXITCODE -ne 0) { throw "Falha: $test" }
}
```

Esses testes cobrem modelos/rolls, conservação de munição, attachments/rerolls, efeitos de combate, navegação, Faro, progressão prolongada, recuperação de saves, configurações e integração da expedição/UI. `test_run.gd` é um alias de `test_expedition.gd`. `render_showcase.gd`, executado **sem `--headless`**, produz capturas para revisão visual em `test-output/`; testes automatizados não substituem jogar e avaliar ritmo, legibilidade e som.

`test_settings_ui.gd -- --capture`, sem `--headless`, exercita os controles com a GPU e registra FOV/qualidade em `test-output/settings-regression/`. `render_combat_feedback.gd` registra fichas de loot e dano sofrido em `test-output/combat-feedback/`; acrescente `-- --large-ui` para repetir com interface em 1,3×. Todos usam saves e preferências de teste isolados.

`.godot/` e `test-output/` são caches/artefatos locais ignorados pelo Git. O protótipo web permanece na raiz do repositório; este projeto nativo tem sua própria execução e seus próprios saves.
