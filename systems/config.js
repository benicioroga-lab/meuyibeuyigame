// Combat balance lives here. Rates are shots/second, angles are radians, times are seconds.
export const WEAPONS = [
  {id:'biscuit',name:'Biscoiteira 12',category:'PISTOLA',description:'Dois bons tiros. Um começo confiável.',damage:22,fireRate:3.2,magazineSize:12,reserveAmmo:84,maxReserve:96,reloadTime:1.25,recoil:.009,spread:.002,aimSpread:0,range:75,price:0,unlockRound:1,color:'#eab96f',sound:220,effect:'kinetic',criticalChance:.05,projectileSpeed:0},
  {id:'boardwalk',name:'Calçadão',category:'CARABINA',description:'Rápida e precisa, mesmo à distância.',damage:26,fireRate:5.2,magazineSize:18,reserveAmmo:126,maxReserve:144,reloadTime:1.5,recoil:.007,spread:.005,aimSpread:0,range:90,price:420,unlockRound:2,color:'#8fcab7',sound:310,effect:'kinetic',criticalChance:.06,projectileSpeed:0},
  {id:'hammer',name:'Marreta',category:'PESADA',description:'Um impacto seco. Perfura até dois inimigos.',damage:70,fireRate:1.3,magazineSize:6,reserveAmmo:42,maxReserve:54,reloadTime:2.1,recoil:.025,spread:.003,aimSpread:0,range:105,price:950,unlockRound:4,color:'#e49478',sound:90,effect:'pierce',pierce:2,criticalChance:.1,projectileSpeed:0},
  {id:'popcorn',name:'Pipoqueira',category:'AUTOMÁTICA',description:'Rajadas longas. Controle a dispersão com a mira.',damage:18,fireRate:11,magazineSize:36,reserveAmmo:216,maxReserve:288,reloadTime:1.8,recoil:.004,spread:.015,aimSpread:.003,range:62,price:1350,unlockRound:6,color:'#dbb8e5',sound:420,effect:'kinetic',criticalChance:.05,projectileSpeed:0},
  {id:'ember',name:'Brasa',category:'INCENDIÁRIA',description:'Acende o alvo. Queima por mais 3 segundos.',damage:32,fireRate:5,magazineSize:24,reserveAmmo:144,maxReserve:192,reloadTime:1.9,recoil:.009,spread:.005,aimSpread:0,range:82,price:2000,unlockRound:8,color:'#ffad69',sound:170,effect:'burn',burnDamage:9,burnDuration:3,criticalChance:.08,projectileSpeed:0},
  {id:'voltage',name:'Voltagem',category:'ELÉTRICA',description:'O choque salta para dois alvos próximos.',damage:42,fireRate:3.8,magazineSize:16,reserveAmmo:96,maxReserve:128,reloadTime:2,recoil:.01,spread:.002,aimSpread:0,range:88,price:3000,unlockRound:10,color:'#9fe4f0',sound:660,effect:'chain',chainTargets:2,chainRadius:5,chainDamage:.45,criticalChance:.08,projectileSpeed:0},
  {id:'zero',name:'Zero Grau',category:'CRIOIMPACTO',description:'Impacto em área. Desacelera a horda sem cobrir sua visão.',damage:62,fireRate:2.1,magazineSize:10,reserveAmmo:60,maxReserve:90,reloadTime:2.2,recoil:.017,spread:.003,aimSpread:0,range:82,price:4000,unlockRound:12,color:'#b8d5ff',sound:130,effect:'frost',radius:2.6,splashDamage:.42,slow:.5,slowDuration:2.5,criticalChance:.1,projectileSpeed:0},
];
export const WEAPON_BY_ID = Object.fromEntries(WEAPONS.map(weapon=>[weapon.id,Object.freeze(weapon)]));
export const WEAPON_UPGRADES = {
  damage:{name:'Núcleo de impacto',max:3,baseCost:180,costScale:1.8},
  magazine:{name:'Pente estendido',max:2,baseCost:150,costScale:1.9},
  reload:{name:'Mecanismo rápido',max:3,baseCost:130,costScale:1.75},
};
export const ENEMY_CONFIG = {
  grunt:{name:'Lata-ligeira',hp:42,speed:1.8,maxSpeed:3.6,speedGrowth:.10,damage:8,reward:24,scale:1,unlockRound:1,color:'#c38268',type:'melee',resist:{}},
  runner:{name:'Corre-corre',hp:28,speed:2.6,maxSpeed:4.6,speedGrowth:.12,damage:6,reward:26,scale:.85,unlockRound:3,color:'#e5b25e',type:'zigzag',resist:{}},
  tank:{name:'Latão',hp:110,speed:1.3,maxSpeed:2.6,speedGrowth:.07,damage:15,reward:55,scale:1.25,unlockRound:5,color:'#85a19b',type:'tank',resist:{kinetic:.12}},
  slinger:{name:'Estilinga',hp:52,speed:1.65,maxSpeed:3.1,speedGrowth:.09,damage:7,reward:38,scale:1,unlockRound:7,color:'#8b90b4',type:'ranged',resist:{burn:.3}},
  captain:{name:'Rei da Sucata',hp:280,speed:1.55,maxSpeed:2.9,speedGrowth:.06,damage:18,reward:180,scale:1.65,unlockRound:5,color:'#a69061',type:'miniboss',resist:{frost:.2}},
};
export function enemyStats(type, round=1) {
  const config=ENEMY_CONFIG[type]||ENEMY_CONFIG.grunt;
  const stage=Math.max(0,round-1);
  // HP soft-caps; late difficulty shifts to composition and pressure, never runaway speed/HP.
  const healthScale=1+Math.min(stage,11)*.095+Math.min(Math.max(0,stage-11),18)*.025;
  return {...config,id:type,hp:Math.round(config.hp*healthScale),speed:Math.min(config.maxSpeed,config.speed+stage*config.speedGrowth),damage:Math.round(config.damage*(1+Math.min(stage,24)*.025)),reward:Math.round(config.reward*(1+Math.min(stage,30)*.035))};
}
export function wavePlan(round) {
  const count=Math.min(30,5+round*2),types=[];
  for(let i=0;i<count;i++)types.push(round>=7&&i%7===4?'slinger':round>=5&&i%6===2?'tank':round>=3&&i%4===1?'runner':'grunt');
  if(round%5===0)types.push('captain');
  return {round,types,target:types.length,special:round%5===0,reward:100+Math.min(round,30)*45,rest:12};
}
export const DOG_CONFIG = {name:'Faro',damage:14,attackCooldown:1.35,speed:6,maxSpeed:8,health:70,leash:14,attackRange:1.7,reviveTime:9};
export const DOG_UPGRADES = {
  bite:{name:'Mordida certeira',description:'Mais dano em cada ataque.',max:5,baseCost:120,costScale:1.6,unlockRound:1},
  tempo:{name:'Instinto de caça',description:'Menos tempo entre ataques.',max:3,baseCost:160,costScale:1.7,unlockRound:2},
  agility:{name:'Patas de vento',description:'Persegue e volta mais rápido.',max:3,baseCost:100,costScale:1.65,unlockRound:1},
  guard:{name:'Coleira protetora',description:'Mais vida e resistência.',max:3,baseCost:150,costScale:1.75,unlockRound:2},
  instinct:{name:'Faro de crítico',description:'Chance de mordidas críticas.',max:3,baseCost:180,costScale:1.7,unlockRound:3},
  pack:{name:'Ataque de matilha',description:'Alcança mais inimigos por mordida.',max:2,baseCost:300,costScale:2,unlockRound:4},
  element:{name:'Lenda do calçadão',description:'Choque → gelo → execução e onda elétrica.',max:3,baseCost:420,costScale:2.1,unlockRound:3},
};
export function dogStats(levels={}) {
  return {...DOG_CONFIG,damage:DOG_CONFIG.damage+(levels.bite||0)*7,attackCooldown:Math.max(.65,DOG_CONFIG.attackCooldown-(levels.tempo||0)*.2),speed:Math.min(DOG_CONFIG.maxSpeed,DOG_CONFIG.speed+(levels.agility||0)*.65),health:DOG_CONFIG.health+(levels.guard||0)*35,resistance:(levels.guard||0)*.1,criticalChance:.05+(levels.instinct||0)*.08,targets:1+(levels.pack||0),element:levels.element||0,level:1+Object.values(levels).reduce((sum,n)=>sum+n,0)};
}
export const ECONOMY={ammoCratesPerWave:2,ammoPickupFraction:.3,ammoShopBase:35,ammoShopRoundScale:3,dogHealCost:40};
