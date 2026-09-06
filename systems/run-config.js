// Run balance: seconds, world units/second and multiplicative factors unless named Chance.
// Difficulty changes are chosen before a run. The director never secretly changes damage.
export const DIFFICULTIES = [
  {id:'easy',name:'Fácil',description:'Espaço para aprender e explorar.',health:.78,damage:.65,speed:.82,aggression:.85,count:.78,specialChance:.65,specialUnlock:-1,reward:.85,xp:.9,lootChance:.85,lootQuality:0,color:'#9fd5b7'},
  {id:'normal',name:'Normal',description:'Pressão justa. Toda escolha importa.',health:1,damage:1.1,speed:1.24,aggression:1.13,count:1,specialChance:1,specialUnlock:0,reward:1,xp:1,lootChance:1,lootQuality:0,color:'#e9c990'},
  {id:'hard',name:'Difícil',description:'Mais ameaças, melhores achados.',health:1.2,damage:1.28,speed:1.35,aggression:1.27,count:1.2,specialChance:1.2,specialUnlock:1,reward:1.3,xp:1.2,lootChance:1.2,lootQuality:.07,color:'#eaaa72'},
  {id:'insane',name:'Insano',description:'Elites cedo. Pouco espaço para errar.',health:1.42,damage:1.48,speed:1.46,aggression:1.4,count:1.35,specialChance:1.45,specialUnlock:2,reward:1.65,xp:1.45,lootChance:1.4,lootQuality:.13,color:'#db8c92'},
  {id:'nightmare',name:'Pesadelo',description:'O morro inteiro contra a sua build.',health:1.65,damage:1.7,speed:1.58,aggression:1.55,count:1.5,specialChance:1.7,specialUnlock:3,reward:2.05,xp:1.7,lootChance:1.65,lootQuality:.2,color:'#b4a0ef'},
];
export const DIFFICULTY_BY_ID=Object.fromEntries(DIFFICULTIES.map(value=>[value.id,Object.freeze(value)]));
export const CHAOS_LEVELS = [
  {level:0,name:'Desligado',description:'A velocidade cresce com os rounds.',speedFloor:0,health:1,damage:1,count:1,reward:1,xp:1,lootChance:1,lootQuality:0},
  {level:1,name:'Chaos I',description:'A horda começa perto da velocidade máxima.',speedFloor:.9,health:1.08,damage:1.08,count:1.08,reward:1.4,xp:1.2,lootChance:1.3,lootQuality:.06},
  {level:2,name:'Chaos II',description:'Velocidade máxima e elites mais cedo.',speedFloor:1,health:1.16,damage:1.16,count:1.13,reward:1.7,xp:1.35,lootChance:1.5,lootQuality:.1},
  {level:3,name:'Chaos III',description:'Elites combinam dois modificadores.',speedFloor:1,health:1.25,damage:1.24,count:1.18,reward:2,xp:1.5,lootChance:1.7,lootQuality:.14},
  {level:4,name:'Chaos IV',description:'Mais composições especiais e pressão.',speedFloor:1,health:1.35,damage:1.32,count:1.23,reward:2.3,xp:1.65,lootChance:1.9,lootQuality:.18},
  {level:5,name:'Chaos V',description:'A Liga não dá trégua. Loot excepcional.',speedFloor:1,health:1.45,damage:1.4,count:1.28,reward:2.6,xp:1.8,lootChance:2.1,lootQuality:.23},
];

export const POWERUPS = {
  infiniteAmmo:{id:'infiniteAmmo',name:'Pente sem fim',description:'Dispare sem consumir munição por 16 s.',icon:'∞',color:'#a9deef',duration:16,weight:1,effect:'infiniteAmmo'},
  doubleDamage:{id:'doubleDamage',name:'Impacto dobrado',description:'Dano ×2 por 18 s.',icon:'×2',color:'#eda78c',duration:18,weight:1,effect:'doubleDamage'},
  frenzy:{id:'frenzy',name:'Arrancada',description:'Cadência +45% e movimento +18% por 16 s.',icon:'»',color:'#e3c284',duration:16,weight:1,effect:'frenzy'},
  nuke:{id:'nuke',name:'Pulso de silêncio',description:'Dano massivo à horda atual.',icon:'◎',color:'#d6b5ef',duration:0,weight:.24,effect:'nuke'},
  magnet:{id:'magnet',name:'Faro magnético',description:'Puxe dinheiro, munição e loot por 24 s.',icon:'↟',color:'#94d6bf',duration:24,weight:1,effect:'magnet'},
  jackpot:{id:'jackpot',name:'Bolada',description:'Um grande bônus de petiscos.',icon:'$',color:'#f3d286',duration:0,weight:.6,effect:'coins'},
  overcharge:{id:'overcharge',name:'Sobrecarga',description:'Seus tiros alternam fogo, choque e gelo por 20 s.',icon:'ϟ',color:'#89dfdf',duration:20,weight:.75,effect:'overcharge'},
};

export const PERKS = {
  quickHands:{id:'quickHands',name:'Mãos ligeiras',description:'Recarga 12% mais rápida por nível.',icon:'↻',max:3,tags:['reload'],cost:240},
  ironSkin:{id:'ironSkin',name:'Casca grossa',description:'Vida máxima +18% e resistência +4% por nível.',icon:'◇',max:3,tags:['survival'],cost:260},
  deadeye:{id:'deadeye',name:'Olho de águia',description:'Crítico +8 pontos percentuais e dano crítico +12%.',icon:'⊕',max:3,tags:['critical'],cost:280},
  lightweight:{id:'lightweight',name:'Passo leve',description:'Movimento +6% por nível.',icon:'»',max:3,tags:['movement'],cost:220},
  ammoHoarder:{id:'ammoHoarder',name:'Bolso fundo',description:'Reserva máxima +25% por nível.',icon:'▤',max:3,tags:['ammo'],cost:200},
  secondWind:{id:'secondWind',name:'Último fôlego',description:'Uma chance de levantar com uma kill. Recupera a carga após 3 rounds.',icon:'↗',max:1,tags:['survival','kill'],cost:600},
  recycle:{id:'recycle',name:'Ciclo fechado',description:'Kills devolvem 5% do pente a partir da reserva por nível.',icon:'⟳',max:3,tags:['ammo','kill'],cost:320},
  headburst:{id:'headburst',name:'Eco certeiro',description:'Headshots fatais explodem com 25% do dano por nível.',icon:'✧',max:3,tags:['critical','area'],cost:380},
  conductor:{id:'conductor',name:'Condutor',description:'Choques alcançam um alvo adicional por nível.',icon:'ϟ',max:2,tags:['element','area'],cost:340},
  catalyst:{id:'catalyst',name:'Catalisador',description:'Dano elemental +15% por nível.',icon:'∆',max:3,tags:['element'],cost:320},
  momentum:{id:'momentum',name:'Embalado',description:'Kills recentes dão +4% de cadência, até 20% por nível.',icon:'≋',max:2,tags:['kill','cadence'],cost:340},
  bond:{id:'bond',name:'Dupla de respeito',description:'Faro causa +15% de dano e ataca 7% mais rápido.',icon:'♧',max:3,tags:['dog'],cost:280},
  recovery:{id:'recovery',name:'Pique renovado',description:'Kills recuperam 1 de vida por nível.',icon:'+',max:3,tags:['kill','survival'],cost:350},
  penetrator:{id:'penetrator',name:'Linha de frente',description:'Balas perfuram um inimigo adicional por nível.',icon:'→',max:2,tags:['precision'],cost:380},
  riskTaker:{id:'riskTaker',name:'Tudo ou nada',description:'Dano +12%; vida máxima −8% por nível.',icon:'!',max:2,tags:['damage','risk'],cost:300},
  supply:{id:'supply',name:'Reserva de emergência',description:'Reabasteça suas armas em 50%.',icon:'▤',max:Infinity,tags:['supply'],effect:'ammo',value:.5},
  payday:{id:'payday',name:'Adiantamento',description:'Receba petiscos para a próxima melhoria.',icon:'$',max:Infinity,tags:['supply'],effect:'coins'},
  patchUp:{id:'patchUp',name:'Fôlego novo',description:'Recupere 60 de vida e reanime Faro.',icon:'+',max:Infinity,tags:['supply'],effect:'heal',value:60},
};

export const RUN_EVENTS = {
  blackout:{id:'blackout',name:'Apagão no morro',description:'A iluminação cai. As luzes da Liga denunciam a horda.',duration:40,unlockRound:4,color:'#b1b4d6',modifiers:{visibility:.48}},
  redmoon:{id:'redmoon',name:'Lua de ferrugem',description:'A horda ataca mais rápido; recompensas aumentam.',duration:42,unlockRound:6,color:'#e69d8e',modifiers:{aggression:1.2,reward:1.25}},
  eliteInvasion:{id:'eliteInvasion',name:'Sinal de invasão',description:'Elites tomam as vielas. Prepare sua build.',duration:38,unlockRound:8,color:'#c3a6e0',modifiers:{eliteChance:.24,lootChance:1.35}},
  doubleLoot:{id:'doubleLoot',name:'Carga extraviada',description:'O dobro de chances de loot.',duration:40,unlockRound:3,color:'#efcf8e',modifiers:{lootChance:2}},
  armsDealer:{id:'armsDealer',name:'Mercado relâmpago',description:'Um vendedor traz peças raras por tempo limitado.',duration:90,unlockRound:5,color:'#93ccb1',modifiers:{shopDiscount:.8}},
  bossHunt:{id:'bossHunt',name:'Frequência proibida',description:'Um sinal raro revela uma caçada opcional.',duration:75,unlockRound:12,color:'#d798a5',modifiers:{bossHunt:true}},
};

export const ROUND_MUTATORS = {
  pursuit:{id:'pursuit',name:'Perseguição',description:'Velocidade base +20%, respeitando o limite de cada classe.',speed:1.2},
  elitePatrol:{id:'elitePatrol',name:'Patrulha de elite',description:'Mais elites na composição da horda.',eliteChance:.12},
  charged:{id:'charged',name:'Liga energizada',description:'Elites elementais aparecem com frequência.',elemental:true,eliteChance:.08},
  reinforcement:{id:'reinforcement',name:'Reforços',description:'Mais inimigos na fila, sem lotar o mapa.',count:1.16},
  armored:{id:'armored',name:'Placas reforçadas',description:'Alguns inimigos ganham resistência cinética; corrosão ganha valor.',resistance:.12},
  supportNetwork:{id:'supportNetwork',name:'Rede de apoio',description:'Suportes e escudos aparecem mais vezes.',supportWeight:1.7},
  apocalypse:{id:'apocalypse',name:'Maré do Ruído',description:'Composições completas, elites duplas e recompensas maiores.',count:1.2,eliteChance:.1,reward:1.25},
};

export const RUN_BALANCE = Object.freeze({
  preparation:4,intermission:10,choiceEvery:3,maxConcurrent:38,maxQueuedPerRound:140,
  baseDropChance:.11,powerupChance:.021,powerupDropCooldown:16,
  comboWindow:3.2,momentumWindow:6,recoveryWindow:2.8,maxRecoveryPause:5.5,
  minSpawnInterval:.24,maxSpawnInterval:2.1,baseEventGap:105,
  lateHealthStart:30,lateHealthSlope:.2,lateHealthCap:2.15,lateDamageCap:1.35,maxFormation:4,
});
