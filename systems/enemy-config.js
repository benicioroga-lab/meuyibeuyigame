// The Liga do Ruído is a fictional raiding faction. Civilians never enter this roster.
export const FACTION={id:'noise-league',name:'Liga do Ruído',emblem:'duas barras quebradas',color:'#f0ba62'};

export const ENEMY_CONFIG={
  grunt:{name:'Batedor do Ruído',hp:42,speed:1.8,maxSpeed:3.6,speedGrowth:.1,damage:8,reward:24,scale:1,unlockRound:1,color:'#de9567',type:'melee',attackCooldown:1.3,attackRange:1.35,resist:{}},
  runner:{name:'Correio',hp:28,speed:2.6,maxSpeed:4.6,speedGrowth:.12,damage:6,reward:26,scale:.85,unlockRound:3,color:'#edbe5a',type:'zigzag',attackCooldown:1,attackRange:1.3,resist:{}},
  tank:{name:'Blindado',hp:110,speed:1.3,maxSpeed:2.6,speedGrowth:.07,damage:15,reward:55,scale:1.25,unlockRound:5,color:'#83a6a0',type:'tank',attackCooldown:1.8,attackRange:1.5,resist:{kinetic:.12,corrosive:-.3}},
  brute:{name:'Demolidor',hp:145,speed:1.15,maxSpeed:2.4,speedGrowth:.065,damage:26,reward:65,scale:1.5,unlockRound:6,color:'#cd8763',type:'brute',attackCooldown:2.5,attackRange:2.5,windup:.85,resist:{kinetic:.08,corrosive:-.25}},
  exploder:{name:'Estopim',hp:36,speed:2.15,maxSpeed:4.2,speedGrowth:.11,damage:28,reward:38,scale:.96,unlockRound:4,color:'#f29355',type:'exploder',attackCooldown:3,attackRange:2.3,windup:.8,explosionRadius:3.3,resist:{burn:.3}},
  slinger:{name:'Sinaleiro',hp:52,speed:1.65,maxSpeed:3.1,speedGrowth:.09,damage:7,reward:38,scale:1,unlockRound:7,color:'#a995cf',type:'ranged',attackCooldown:2.3,attackRange:13,windup:.35,resist:{burn:.3}},
  shield:{name:'Vanguarda',hp:72,shieldHealth:90,speed:1.4,maxSpeed:2.8,speedGrowth:.075,damage:12,reward:48,scale:1.12,unlockRound:5,color:'#90a9bd',type:'shield',attackCooldown:1.8,attackRange:1.7,resist:{corrosive:-.25}},
  berserker:{name:'Fúria',hp:68,speed:1.8,maxSpeed:4.2,speedGrowth:.1,damage:12,reward:44,scale:1.1,unlockRound:8,color:'#d77f83',type:'berserker',attackCooldown:1.35,attackRange:1.55,resist:{}},
  assassin:{name:'Vulto',hp:40,speed:2.5,maxSpeed:4.5,speedGrowth:.12,damage:14,reward:50,scale:.94,unlockRound:9,color:'#9195bd',type:'assassin',attackCooldown:1.7,attackRange:1.45,leapCooldown:5,resist:{}},
  support:{name:'Frequência',hp:66,speed:1.5,maxSpeed:2.9,speedGrowth:.075,damage:5,reward:62,scale:1.04,unlockRound:10,color:'#84baa3',type:'support',attackCooldown:3.3,attackRange:12,healRadius:6,healCooldown:4,resist:{}},
  captain:{name:'Capitão da Interferência',hp:280,speed:1.55,maxSpeed:2.9,speedGrowth:.06,damage:18,reward:180,scale:1.65,unlockRound:5,color:'#b69a65',type:'miniboss',attackCooldown:2.2,attackRange:2.1,resist:{frost:.2}},
};
// Public alias lets the director use either vocabulary without duplicating balance.
ENEMY_CONFIG.ranged=ENEMY_CONFIG.slinger;
export const ENEMY_CLASSES=ENEMY_CONFIG;
export const ELITE_MODIFIERS={
  fire:{id:'fire',name:'Incendiário',color:'#ffa262',resist:{burn:.45},effect:'burn'},
  shock:{id:'shock',name:'Elétrico',color:'#89e1e9',resist:{chain:.45,shock:.45},effect:'shock'},
  frost:{id:'frost',name:'Congelante',color:'#aabff8',resist:{frost:.45,cryo:.45},effect:'frost'},
  vampiric:{id:'vampiric',name:'Vampírico',color:'#cc93bf',resist:{},effect:'lifesteal'},
  volatile:{id:'volatile',name:'Instável',color:'#eec170',resist:{},effect:'death-explosion'},
  frenzied:{id:'frenzied',name:'Frenético',color:'#e37e89',resist:{},effect:'frenzy'},
};
const modifierIds=Object.keys(ELITE_MODIFIERS);
export function eliteModifiers(seed=0,count=1){
  const first=Math.abs(Math.trunc(seed))%modifierIds.length;
  return Array.from({length:Math.min(modifierIds.length,Math.max(0,count))},(_,i)=>ELITE_MODIFIERS[modifierIds[(first+i*5)%modifierIds.length]]);
}
export function normalizeElite(elite){
  if(!elite)return [];
  const list=Array.isArray(elite)?elite:elite.modifiers||[elite];
  const seen=new Set();return list.map(value=>typeof value==='string'?ELITE_MODIFIERS[value]:{...ELITE_MODIFIERS[value.id],...value}).filter(value=>value?.id&&!seen.has(value.id)&&seen.add(value.id));
}
export function enemyStats(type='grunt',round=1,overrides={}){
  const base=ENEMY_CONFIG[type]||ENEMY_CONFIG.grunt,stage=Math.max(0,(Number.isFinite(round)?round:1)-1);
  // Hit-point growth soft caps. High-round pressure comes from the director and composition.
  const healthScale=1+Math.min(stage,11)*.095+Math.min(Math.max(stage-11,0),18)*.025;
  const result={...base,id:type,faction:FACTION.id,aggression:1,hp:Math.round(base.hp*healthScale),speed:Math.min(base.maxSpeed,base.speed+stage*base.speedGrowth),damage:Math.round(base.damage*(1+Math.min(stage,24)*.025)),reward:Math.round(base.reward*(1+Math.min(stage,30)*.035)),...overrides};
  result.resist={...base.resist,...overrides.resist};
  result.speed=Math.max(.1,Math.min(result.maxSpeed,result.speed));result.hp=Math.max(1,Math.round(result.hp));
  return result;
}
export const resolveEnemyStats=enemyStats;
