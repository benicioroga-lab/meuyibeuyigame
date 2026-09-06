import {WEAPONS} from './config.js';

// All rates are rounds/second; damage is total per trigger, shared between pellets.
export const LOOT_WEAPONS = Object.freeze([...WEAPONS,
  {id:'cascade',name:'Cascata',category:'ESCOPETA',family:'shotgun',description:'Oito projéteis. Domina vielas, perde força à distância.',damage:96,fireRate:1.15,magazineSize:6,reserveAmmo:36,maxReserve:60,reloadTime:2.15,recoil:.035,spread:.075,aimSpread:.04,range:32,price:650,unlockRound:3,color:'#dfa977',sound:78,effect:'kinetic',criticalChance:.04,criticalMultiplier:1.5,pellets:8,projectileSpeed:0},
  {id:'horizon',name:'Horizonte',category:'PRECISÃO',family:'sniper',description:'Mira ampliada, perfuração e alto impacto na cabeça.',damage:94,fireRate:.85,magazineSize:5,reserveAmmo:30,maxReserve:50,reloadTime:2.45,recoil:.032,spread:.024,aimSpread:0,range:145,price:1150,unlockRound:5,color:'#bad1cc',sound:64,effect:'pierce',pierce:3,criticalChance:.12,criticalMultiplier:2.1,zoom:1.6,projectileSpeed:0},
  {id:'firefly',name:'Vagalume',category:'SMG',family:'smg',description:'Leve, rápida e feita para reagir de perto.',damage:15,fireRate:13,magazineSize:32,reserveAmmo:192,maxReserve:256,reloadTime:1.4,recoil:.004,spread:.019,aimSpread:.004,range:48,price:800,unlockRound:4,color:'#b5d888',sound:470,effect:'kinetic',criticalChance:.06,handling:85,projectileSpeed:0},
].map(weapon=>Object.freeze({...weapon,family:weapon.family||({PISTOLA:'pistol',CARABINA:'rifle',PESADA:'heavy',AUTOMÁTICA:'smg'}[weapon.category]||'rifle'),pellets:weapon.pellets||1,criticalMultiplier:weapon.criticalMultiplier||1.65,handling:weapon.handling||65,zoom:weapon.zoom||1})));
export const LOOT_WEAPON_BY_ID=Object.freeze(Object.fromEntries(LOOT_WEAPONS.map(weapon=>[weapon.id,weapon])));

export const RARITIES=Object.freeze({
  common:{id:'common',name:'Comum',label:'COMMON',color:'#c6ccc5',symbol:'○',weight:58,power:1,affixes:1,slots:1,scrap:25},
  uncommon:{id:'uncommon',name:'Incomum',label:'UNCOMMON',color:'#9dd593',symbol:'◇',weight:27,power:1.07,affixes:2,slots:2,scrap:50},
  rare:{id:'rare',name:'Rara',label:'RARE',color:'#84c6ed',symbol:'◆',weight:10,power:1.14,affixes:3,slots:3,scrap:90},
  epic:{id:'epic',name:'Épica',label:'EPIC',color:'#c3a0eb',symbol:'✦',weight:3.8,power:1.22,affixes:4,slots:4,scrap:150},
  legendary:{id:'legendary',name:'Lendária',label:'LEGENDARY',color:'#ffc572',symbol:'★',weight:1,power:1.29,affixes:5,slots:5,scrap:260},
  mythic:{id:'mythic',name:'Mítica',label:'MYTHIC',color:'#f89cbb',symbol:'✺',weight:.2,power:1.35,affixes:6,slots:6,scrap:420},
});
export const MANUFACTURERS=Object.freeze({
  faisca:{id:'faisca',name:'Faísca Oficina',description:'Motores rápidos; exige controlar o recuo.',mods:{fireRate:1.14,recoil:1.13,damage:.95}},
  fundicao:{id:'fundicao',name:'Fundição Sete',description:'Massa e impacto, cadência deliberada.',mods:{damage:1.16,fireRate:.9,recoil:1.18}},
  prisma:{id:'prisma',name:'Prisma Circuitos',description:'Elementos e recarga eficiente.',mods:{reloadTime:.91,damage:.97},elemental:true},
  muralha:{id:'muralha',name:'Muralha Industrial',description:'Reservas grandes; mecanismos pesados.',mods:{magazineSize:1.25,maxReserve:1.15,reloadTime:1.12,handling:.88}},
  agulha:{id:'agulha',name:'Agulha Óptica',description:'Precisão e crítico; pentes compactos.',mods:{spread:.7,aimSpread:.65,magazineSize:.9},crit:.06},
  remendo:{id:'remendo',name:'Remendo Oficina',description:'Peças experimentais: versatilidade com recuo.',mods:{damage:1.05,magazineSize:1.08,recoil:1.14}},
});
export const ATTACHMENT_SLOTS=Object.freeze(['scope','barrel','magazine','receiver','stock','ammo']);
export const SLOT_NAMES=Object.freeze({scope:'Óptica',barrel:'Cano',magazine:'Pente',receiver:'Mecanismo',stock:'Coronha',ammo:'Munição'});
export const ATTACHMENTS=Object.freeze({
  dot:{id:'dot',slot:'scope',name:'Ponto âmbar',price:90,mods:{spread:.86,aimSpread:.7},crit:.025,zoom:1.1},
  marksman:{id:'marksman',slot:'scope',name:'Lente panorâmica',price:170,mods:{aimSpread:.35,handling:.92},crit:.06,zoom:1.6},
  laser:{id:'laser',slot:'scope',name:'Laser de corredor',price:140,mods:{spread:.58,handling:1.07}},
  compensator:{id:'compensator',slot:'barrel',name:'Freio de recuo',price:150,mods:{recoil:.67,range:.92}},
  longbarrel:{id:'longbarrel',slot:'barrel',name:'Cano de precisão',price:180,mods:{range:1.3,damage:1.08,handling:.9}},
  furnace:{id:'furnace',slot:'barrel',name:'Câmara de brasas',price:260,mods:{damage:.96},element:'fire'},
  suppressor:{id:'suppressor',slot:'barrel',name:'Abafador de cerâmica',price:160,mods:{range:.85,recoil:.82},silenced:true},
  extended:{id:'extended',slot:'magazine',name:'Pente alongado',price:150,mods:{magazineSize:1.35,reloadTime:1.13}},
  quickmag:{id:'quickmag',slot:'magazine',name:'Engate rápido',price:180,mods:{magazineSize:.85,reloadTime:.7}},
  alternator:{id:'alternator',slot:'magazine',name:'Pente alternador',price:380,mods:{magazineSize:.9},alternatingElements:['fire','shock','cryo']},
  overclock:{id:'overclock',slot:'receiver',name:'Motor acelerado',price:220,mods:{fireRate:1.22,damage:.92,recoil:1.1}},
  burst:{id:'burst',slot:'receiver',name:'Tríade mecânica',price:280,mods:{damage:1.1,fireRate:.83},burstCount:3,burstInterval:.075},
  precision:{id:'precision',slot:'receiver',name:'Percussor fino',price:240,mods:{fireRate:.9,damage:1.1},crit:.05},
  balanced:{id:'balanced',slot:'stock',name:'Apoio equilibrado',price:100,mods:{recoil:.82,handling:1.1}},
  lightweight:{id:'lightweight',slot:'stock',name:'Estrutura vazada',price:160,mods:{handling:1.24,recoil:1.12},moveSpeed:1.04},
  shockcell:{id:'shockcell',slot:'ammo',name:'Célula de arco',price:320,element:'shock'},
  cryocell:{id:'cryocell',slot:'ammo',name:'Carga criogênica',price:320,element:'cryo'},
  acidcell:{id:'acidcell',slot:'ammo',name:'Núcleo dissolvente',price:340,element:'corrosive'},
  explosive:{id:'explosive',slot:'ammo',name:'Carga de ruptura',price:420,mods:{damage:.9},element:'explosive'},
  jacketed:{id:'jacketed',slot:'ammo',name:'Núcleo perfurante',price:200,pierce:2},
});
export const ELEMENTS=Object.freeze({
  kinetic:{id:'kinetic',name:'Cinético',effect:'kinetic',color:'#e9c891'},
  fire:{id:'fire',name:'Fogo',effect:'burn',color:'#ffad69',burnDamage:9,burnDuration:3},
  shock:{id:'shock',name:'Choque',effect:'chain',color:'#9fe4f0',chainTargets:2,chainRadius:5,chainDamage:.36},
  cryo:{id:'cryo',name:'Gelo',effect:'frost',color:'#b8d5ff',radius:2,splashDamage:.25,slow:.5,slowDuration:2.5},
  corrosive:{id:'corrosive',name:'Corrosivo',effect:'corrosive',color:'#bcde79',corrosionDamage:7,corrosionDuration:4,armorPierce:.7},
  explosive:{id:'explosive',name:'Explosivo',effect:'explosive',color:'#f5b189',radius:2.5,splashDamage:.45},
});
export const LEGENDARY_PERKS=Object.freeze({
  fifth_arc:{id:'fifth_arc',name:'Quinto Sinal',description:'Cada quinto disparo encadeia um arco elétrico em até 4 alvos.'},
  last_word:{id:'last_word',name:'Ponto Final',description:'A última bala do pente causa 4× dano.'},
  headburst:{id:'headburst',name:'Ideia Explosiva',description:'Abates na cabeça explodem em área.'},
  tempo:{id:'tempo',name:'Embalado',description:'Abates aumentam cadência por 5s, até +40%.'},
  echo:{id:'echo',name:'Eco de Rua',description:'10% de chance de repetir o disparo sem gastar munição.'},
});
export const FORGE_MAX_TIER=5;
export const INVENTORY_LIMIT=16;
export const REFINEMENT_CONFIG=Object.freeze({baseCost:950,levelCost:220,growthCost:70,costExponent:1.35,damageLogGrowth:.06});
export const ITEM_LEVEL_CONFIG=Object.freeze({maxDamageBonus:.32,roundScale:55});
