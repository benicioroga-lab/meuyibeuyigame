import {ENEMY_CONFIG,enemyStats,eliteModifiers} from './enemy-config.js';
import {DIFFICULTY_BY_ID,CHAOS_LEVELS,PERKS,POWERUPS,RUN_EVENTS,ROUND_MUTATORS,RUN_BALANCE} from './run-config.js';

const clamp=(value,min,max)=>Math.min(max,Math.max(min,value));
const valid=(value,fallback=0)=>Number.isFinite(value)?value:fallback;
const pointOf=enemy=>{const p=enemy?.g?.position||enemy?.position;return p?{x:valid(p.x),y:valid(p.y),z:valid(p.z)}:null;};
const perkValue=(id,level)=>({quickHands:`−${level*12}% de recarga`,ironSkin:`+${level*18}% vida / ${level*4}% resistência`,deadeye:`+${level*8}% crítico / +${level*12}% dano crítico`,lightweight:`+${level*6}% movimento`,ammoHoarder:`+${level*25}% reserva`,secondWind:`${level} chance de levantar`,recycle:`${level*5}% do pente por kill`,headburst:`${level*25}% de explosão`,conductor:`+${level} alvo elétrico`,catalyst:`+${level*15}% dano elemental`,momentum:`até +${level*20}% cadência`,bond:`+${level*15}% dano Faro / −${level*7}% intervalo`,recovery:`${level} vida por kill`,penetrator:`+${level} alvo perfurado`,riskTaker:`+${level*12}% dano / −${level*8}% vida`}[id]);
let runSerial=0;
export function runRandom(seed=1){let state=Math.trunc(valid(seed,1))>>>0;return ()=>{state+=0x6D2B79F5;let value=state;value=Math.imul(value^(value>>>15),value|1);value^=value+Math.imul(value^(value>>>7),value|61);return ((value^(value>>>14))>>>0)/4294967296;};}
function weighted(random,entries){let roll=random()*entries.reduce((total,item)=>total+item.weight,0);for(const item of entries){roll-=item.weight;if(roll<=0)return item;}return entries.at(-1);}
function sample(random,entries,count){const pool=[...entries],result=[];while(pool.length&&result.length<count)result.push(pool.splice(Math.floor(random()*pool.length),1)[0]);return result;}

/** Pure run simulation; no DOM, clocks, persistence or rendering side effects.
 * Call update only while playing. A paused menu therefore freezes all timers.
 * Metrics: healthRatio, ammoRatio [0,1], enemiesAlive, dps, heading (radians).
 * Spawn events contain complete stats; do not apply reward/difficulty multipliers again.
 * The integration sets enemy.roundEnemy=true and enemy.runSpawnId=event.spawnId.
 * onKill is safe to call twice for the same instance. Boss/event actors are roundEnemy=false.
 * Events: spawn; round-start; round-complete; kill; loot-drop; powerup-drop;
 * perk-choice; perk-chosen; powerup-active/expired; event-start/end; milestone;
 * world-boss; rhythm; second-wind-ready/consumed; run-ended.
 */
export class RunDirector {
  constructor({difficulty='normal',chaos=0,seed=1,emit=()=>{},meta=null,runId=null}={}){
    this.difficulty=DIFFICULTY_BY_ID[difficulty]?difficulty:'normal';
    const maxChaos=meta?.state?.maxChaos??5;
    this.chaos=clamp(Math.floor(valid(Number(chaos))),0,clamp(valid(maxChaos,5),0,5));
    this.seed=Math.trunc(valid(seed,1));this.random=runRandom(this.seed);this.runId=runId||`run:${this.seed}:${++runSerial}`;this.emit=emit;
    this.round=1;this.phase='ready';this.remaining=0;this.kills=0;this.target=0;this.spawnQueue=[];this.spawned=0;
    this.timer=RUN_BALANCE.preparation;this.time=0;this.pressure=0;this.spawnClock=0;this.damageClock=99;this.recovery=0;this.recoveryCooldown=0;this.spawnIndex=0;
    this.perkLevels={};this.choices=[];this.powers=new Map();this.mutators=[];this.event=null;this.eventClock=RUN_BALANCE.baseEventGap;
    this.totalKills=0;this.headshots=0;this.bestCombo=0;this.combo=0;this.comboClock=0;this.recentKills=[];this.damageHistory=[];this.recentDamage=0;
    this.lastPowerup=-100;this.lastSupply=-100;this.secondWindCharges=0;this.secondWindRecoverAt=0;this.completedRounds=0;
    this.seenEnemies=new WeakSet();this.seenSpawnIds=new Set();this.metrics={healthRatio:1,ammoRatio:1,enemiesAlive:0,dps:0,heading:0};this.dpsAverage=0;
  }
  get difficultyConfig(){return DIFFICULTY_BY_ID[this.difficulty];}
  get chaosConfig(){return CHAOS_LEVELS[this.chaos];}
  start(){if(this.phase!=='ready')return false;this.phase='preparation';this.timer=RUN_BALANCE.preparation;this.emit({type:'run-start',runId:this.runId,difficulty:this.difficulty,chaos:this.chaos,seed:this.seed});return true;}
  startRound(round=this.round){
    if(this.phase==='dead'||this.phase==='combat'||this.phase==='choice')return false;
    this.round=clamp(Math.floor(valid(round,1)),1,Number.MAX_SAFE_INTEGER-1);this.phase='combat';this.timer=0;this.kills=0;this.spawned=0;this.spawnClock=.35;this.seenSpawnIds.clear();this.recovery=0;
    this.mutators=this.makeMutators();
    const difficulty=this.difficultyConfig,chaos=this.chaosConfig;
    const mutatorCount=this.mutators.reduce((value,item)=>value*(item.count||1),1);
    // A bounded queue and bounded concurrent actors keep an endless run affordable.
    // After the count cap, composition, rotating mutators and elites continue changing.
    this.target=clamp(Math.round((5+this.round*1.65+Math.sqrt(this.round)*.6)*difficulty.count*chaos.count*mutatorCount),5,RUN_BALANCE.maxQueuedPerRound);
    this.remaining=this.target;this.spawnQueue=Array.from({length:this.target},(_,index)=>this.planEnemy(index));
    if(this.round>=75&&this.round%5===0&&this.random()<Math.min(.4,.09+this.chaos*.035+(this.round-75)*.001))this.emit({type:'world-boss',round:this.round,modifiers:this.chaos>=3?2:1});
    this.emit({type:'round-start',round:this.round,target:this.target,mutators:this.mutators.map(value=>({...value})),chaos:this.chaos});return true;
  }
  makeMutators(){
    const result=[];
    if(this.round>=30)result.push(ROUND_MUTATORS.pursuit);
    if(this.round>=35)result.push(ROUND_MUTATORS.elitePatrol);
    if(this.round>=40)result.push(ROUND_MUTATORS.charged);
    if(this.round>=50){const rotating=['reinforcement','armored','supportNetwork'];result.push(...sample(this.random,rotating,this.round>=100?2:1).map(id=>ROUND_MUTATORS[id]));}
    if(this.round>=100)result.push(ROUND_MUTATORS.apocalypse);
    return result;
  }
  planEnemy(index){
    const difficulty=this.difficultyConfig;
    const effectiveRound=this.round+this.chaos*2+difficulty.specialUnlock;
    const special=Math.min(.8,(.16+this.round*.012+this.chaos*.06)*difficulty.specialChance);
    const supports=this.mutators.some(value=>value.id==='supportNetwork')?1.7:1;
    const roster=[{id:'grunt',weight:1-special}];
    const weights={runner:1.5,tank:.8,brute:.5,exploder:.8,slinger:.8,shield:.7,berserker:.7,assassin:.6,support:.5};
    const available=Object.entries(weights).filter(([id])=>effectiveRound>=ENEMY_CONFIG[id].unlockRound);
    const total=available.reduce((sum,[id,weight])=>sum+weight*(['support','shield'].includes(id)?supports:1),0);
    for(const [id,weight]of available)roster.push({id,weight:special*weight*(['support','shield'].includes(id)?supports:1)/(total||1)});
    let enemyType=weighted(this.random,roster).id;
    if(this.round%5===0&&index===this.target-1)enemyType='captain';
    // Guarantee one newly unlocked class in its first wave, instead of requiring lucky rolls.
    const debut=available.find(([id])=>ENEMY_CONFIG[id].unlockRound===effectiveRound);
    if(debut&&index===Math.min(2,this.target-1))enemyType=debut[0];
    const eliteChance=effectiveRound<4?0:clamp((.018+this.round*.003+this.chaos*.035)*difficulty.specialChance+this.mutators.reduce((sum,item)=>sum+(item.eliteChance||0),0),0,.65);
    const elite=this.random()<eliteChance?eliteModifiers(Math.floor(this.random()*100000),this.chaos>=3||this.round>=50?2:1):null;
    return {enemyType,elite,spawnId:`${this.runId}:${this.round}:${index}`};
  }
  statsFor(type,elite=null){
    const base=enemyStats(type,this.round),difficulty=this.difficultyConfig,chaos=this.chaosConfig;
    const speedMultiplier=this.mutators.reduce((value,item)=>value*(item.speed||1),1);
    const speed=Math.min(base.maxSpeed,Math.max(base.speed*difficulty.speed*speedMultiplier,base.maxSpeed*chaos.speedFloor));
    const eliteHealth=elite?.length?1.4:1,eliteReward=elite?.length?1.75:1;
    // Common grunts remain fodder. Durable classes gain a slow, bounded reserve
    // against advanced builds; formations do most of the work in late rounds.
    const lateStage=Math.max(0,this.round-RUN_BALANCE.lateHealthStart),growth=Math.log2(1+lateStage/25);
    const resilience=type==='grunt'&&!elite?.length?1:Math.min(RUN_BALANCE.lateHealthCap,1+growth*RUN_BALANCE.lateHealthSlope);
    const lateDamage=type==='grunt'?1:Math.min(RUN_BALANCE.lateDamageCap,1+growth*.065);
    const rewardMultiplier=this.modifiers.reward;
    const resist={...base.resist};if(this.mutators.some(value=>value.resistance)){resist.kinetic=Math.min(.45,(resist.kinetic||0)+.12);resist.corrosive=Math.min(-.2,resist.corrosive||0);}
    return {...base,hp:Math.round(base.hp*difficulty.health*chaos.health*eliteHealth*resilience),speed,maxSpeed:base.maxSpeed,
      damage:Math.round(base.damage*difficulty.damage*chaos.damage*lateDamage),
      reward:Math.round(base.reward*rewardMultiplier*eliteReward),xp:Math.round((type==='captain'?90:type==='grunt'?14:20)*this.modifiers.xp*(elite?.length?1.65:1)),
      // Enemy AI divides this base cooldown by aggression once; windups retain their tell.
      attackCooldown:base.attackCooldown,
      aggression:difficulty.aggression,resist,runRound:this.round,elite};
  }
  update(dt,metrics={}){
    if(!Number.isFinite(dt)||dt<=0||['ready','dead','choice'].includes(this.phase))return;
    // Catch up deterministically in small steps while bounding accidentally huge timestamps.
    let remaining=Math.min(dt,30);while(remaining>1e-8){const step=Math.min(.1,remaining);this.step(step,metrics);remaining-=step;if(this.phase==='choice'||this.phase==='dead')break;}
  }
  step(dt,metrics){
    for(const key of ['healthRatio','ammoRatio'])if(Number.isFinite(metrics[key]))this.metrics[key]=clamp(metrics[key],0,1);
    for(const key of ['enemiesAlive','dps','heading'])if(Number.isFinite(metrics[key]))this.metrics[key]=key==='heading'?metrics[key]:Math.max(0,metrics[key]);
    this.dpsAverage+=(this.metrics.dps-this.dpsAverage)*Math.min(1,dt*.25);
    this.time+=dt;this.damageClock+=dt;this.comboClock=Math.max(0,this.comboClock-dt);if(!this.comboClock)this.combo=0;
    while(this.recentKills.length&&this.time-this.recentKills[0]>RUN_BALANCE.momentumWindow)this.recentKills.shift();
    while(this.damageHistory.length&&this.time-this.damageHistory[0].time>4)this.damageHistory.shift();
    this.recentDamage=this.damageHistory.reduce((sum,value)=>sum+value.amount,0);
    for(const [id,power]of this.powers){power.time-=dt;if(power.time<=1e-7){this.powers.delete(id);this.emit({type:'powerup-expired',id});}}
    if(this.event){this.event.time-=dt;if(this.event.time<=1e-7)this.endEvent();}
    this.eventClock-=dt;this.recoveryCooldown=Math.max(0,this.recoveryCooldown-dt);
    if(this.phase==='preparation'||this.phase==='intermission'){
      this.timer=Math.max(0,this.timer-dt);if(this.timer<=1e-7)this.startRound();return;
    }
    if(this.phase!=='combat')return;
    if(!this.event&&this.eventClock<=0&&this.round>=3&&this.metrics.healthRatio>.35){this.startEvent();this.eventClock=RUN_BALANCE.baseEventGap+this.random()*50;}
    const alive=Math.max(this.spawned-this.kills,Math.floor(this.metrics.enemiesAlive));
    const capacity=this.concurrentCap;
    const danger=(1-this.metrics.healthRatio)*.48+(1-this.metrics.ammoRatio)*.2+clamp(alive/capacity,0,1)*.25+(this.damageClock<2?.15:0)+(this.dpsAverage>10&&this.metrics.dps<this.dpsAverage*.3?.05:0);
    this.pressure+=((clamp(danger,0,1))-this.pressure)*Math.min(1,dt*1.8);
    const struggling=this.metrics.healthRatio<.3||(this.metrics.ammoRatio<.09&&this.metrics.healthRatio<.65);
    if(struggling&&this.recoveryCooldown<=0&&this.spawnQueue.length&&alive>=3){this.recovery=RUN_BALANCE.maxRecoveryPause;this.recoveryCooldown=22;this.emit({type:'rhythm',phase:'respite',duration:this.recovery});}
    if(this.recovery>0){this.recovery=Math.max(0,this.recovery-dt);return;}
    this.spawnClock-=dt;
    if(this.spawnQueue.length&&alive<capacity&&this.spawnClock<=0){
      // Late waves arrive as readable formations rather than a trickle of isolated
      // enemies. A wounded player still receives single arrivals after a respite.
      const formation=this.pressure>.65||this.metrics.healthRatio<.4?1:Math.min(RUN_BALANCE.maxFormation,1+Number(this.round>=15)+Number(this.round>=30)+Number(this.round>=75)+Number(this.chaos>=3));
      const count=Math.min(this.difficulty==='easy'?Math.min(2,formation):formation,capacity-alive,this.spawnQueue.length);
      for(let index=0;index<count;index++)this.spawnNext();
      const efficiency=clamp(this.recentKills.length/5+Math.min(.2,this.metrics.dps/250),0,1),comfortable=this.metrics.healthRatio>.7&&this.metrics.ammoRatio>.25&&this.damageClock>7;
      const interval=1.8/(1+Math.min(this.round,70)*.035+this.chaos*.12);
      this.spawnClock=clamp(interval*(1+this.pressure*.85)*(comfortable?1-efficiency*.28:1),RUN_BALANCE.minSpawnInterval,RUN_BALANCE.maxSpawnInterval);
    }
  }
  get concurrentCap(){return clamp(Math.round(12+Math.min(18,this.round*.6)+this.chaos*1.5+(this.difficultyConfig.count-1)*8),10,RUN_BALANCE.maxConcurrent);}
  spawnNext(){
    if(!this.spawnQueue.length)return false;
    const next=this.spawnQueue.shift();let elite=next.elite;
    if(!elite&&this.event?.config.id==='eliteInvasion'&&this.random()<.24)elite=eliteModifiers(Math.floor(this.random()*10000),1);
    this.spawned++;this.spawnIndex++;
    // Repeated golden-angle offsets spread entrances. Relief moves spawns into view.
    const flank=this.pressure<.45&&this.damageClock>6?Math.PI*.6:0;
    const heading=valid(this.metrics.heading),angle=heading+Math.sin(this.spawnIndex*2.399963)*1.25+flank;
    this.emit({type:'spawn',...next,elite,stats:this.statsFor(next.enemyType,elite),modifiers:elite||[],round:this.round,angle,distance:18+this.random()*9+(this.pressure>.6?5:0)});return true;
  }
  onKill(enemy,info={}){
    if(!enemy||typeof enemy!=='object'||['dead','ready'].includes(this.phase)||this.seenEnemies.has(enemy))return false;
    const enemyRound=(enemy.config||enemy.stats)?.runRound;
    if(enemy.roundEnemy===true&&Number.isFinite(enemyRound)&&enemyRound!==this.round)return false;
    const spawnId=enemy.runSpawnId||enemy.spawnId;
    if(spawnId&&this.seenSpawnIds.has(spawnId))return false;
    this.seenEnemies.add(enemy);if(spawnId)this.seenSpawnIds.add(spawnId);
    if(info.source==='self'){this.countWaveKill(enemy);return true;}
    this.totalKills++;const headshot=!!info.headshot;if(headshot)this.headshots++;
    this.combo=this.comboClock>0?this.combo+1:1;this.comboClock=RUN_BALANCE.comboWindow;this.bestCombo=Math.max(this.bestCombo,this.combo);this.recentKills.push(this.time);
    const stats=enemy.config||enemy.stats||{},position=pointOf(enemy);
    // statsFor has already applied run rewards; ambient actors without run stats use the same policy once.
    const prepared=Number.isFinite(stats.runRound);
    const reward=Math.round((stats.reward||24)*(prepared?1:this.modifiers.reward));
    const xp=Math.round(prepared?(stats.xp||14):14*this.modifiers.xp);
    // Boss encounters own their guaranteed reward; this path never duplicates it.
    if(enemy.boss||enemy.isBoss){this.countWaveKill(enemy);return true;}
    this.emit({type:'kill',enemy,position,headshot,reward,xp,combo:this.combo,heal:this.perkLevels.recovery||0,damage:valid(info.damage),source:info.source||'weapon'});
    const elite=!!(enemy.elite?.length||stats.elite?.length),lootChance=Math.min(.65,RUN_BALANCE.baseDropChance*this.modifiers.lootChance*(elite?1.8:1));
    if(this.random()<lootChance)this.emit({type:'loot-drop',position,round:this.round,qualityBonus:this.modifiers.lootQuality+(elite?.08:0),source:elite?'elite':'enemy'});
    if(this.time-this.lastPowerup>=RUN_BALANCE.powerupDropCooldown&&this.random()<RUN_BALANCE.powerupChance*(elite?2:1)){
      this.lastPowerup=this.time;const power=weighted(this.random,Object.values(POWERUPS));this.emit({type:'powerup-drop',id:power.id,position});
    }
    if(this.metrics.ammoRatio<.15&&this.time-this.lastSupply>12){this.lastSupply=this.time;this.emit({type:'supply-drop',kind:'ammo',position,fraction:.6});}
    this.countWaveKill(enemy);return true;
  }
  countWaveKill(enemy){
    const stats=enemy.config||enemy.stats||{};
    if(enemy.roundEnemy===true&&(!stats.runRound||stats.runRound===this.round)&&this.phase==='combat'&&this.kills<this.spawned){
      this.kills++;this.remaining=Math.max(0,this.target-this.kills);
      if(this.remaining===0&&!this.spawnQueue.length)this.completeRound();
    }
  }
  onDamage(amount){if(this.phase==='dead'||!Number.isFinite(amount)||amount<=0)return false;this.damageClock=0;this.damageHistory.push({time:this.time,amount});if(this.damageHistory.length>80)this.damageHistory.shift();return true;}
  completeRound(){
    if(this.phase!=='combat'||this.remaining>0||this.spawnQueue.length)return false;
    const completed=this.round;this.completedRounds=Math.max(this.completedRounds,completed);
    const reward=Math.round((100+Math.min(completed,60)*45)*this.modifiers.reward),xp=Math.round((30+Math.min(completed,60)*12)*this.modifiers.xp);
    this.phase='intermission';this.timer=RUN_BALANCE.intermission;this.round=completed+1;
    this.emit({type:'round-complete',round:completed,nextRound:this.round,reward,xp,rest:this.timer,slowMotion:{scale:.3,duration:.34}});
    if(completed%5===0)this.emit({type:'milestone',round:completed,runId:this.runId,encounterId:`${this.runId}:round:${completed}`});
    if(this.perkLevels.secondWind&&this.secondWindCharges===0&&completed>=this.secondWindRecoverAt){this.secondWindCharges=1;this.emit({type:'second-wind-ready'});}
    if(completed%RUN_BALANCE.choiceEvery===0){this.choices=this.rollChoices();this.phase='choice';this.emit({type:'perk-choice',round:completed,choices:this.choices.map(value=>({...value}))});}
    return true;
  }
  rollChoices(){
    const ownedTags=new Set(Object.keys(this.perkLevels).flatMap(id=>PERKS[id]?.tags||[]));
    const pool=Object.values(PERKS).filter(perk=>!perk.effect&&(this.perkLevels[perk.id]||0)<perk.max);
    const selected=[];
    // Offer a build connection, a survivability/utility option, and an open roll.
    for(let index=0;index<3&&pool.length;index++){
      const candidates=pool.map(perk=>({perk,weight:index===0&&perk.tags.some(tag=>ownedTags.has(tag))?2.5:1}));
      const next=weighted(this.random,candidates).perk;selected.push(this.perkPreview(next.id));pool.splice(pool.indexOf(next),1);
    }
    for(const id of ['supply','payday','patchUp'])if(selected.length<3)selected.push(this.perkPreview(id));
    return selected;
  }
  perkPreview(id){const perk=PERKS[id];if(!perk)return null;const level=this.perkLevels[id]||0;return {...perk,level,nextLevel:level+1,current:level,next:level+1,before:perkValue(id,level),after:perkValue(id,Math.min(level+1,perk.max)),cost:perk.cost?Math.round(perk.cost*Math.pow(1.65,level)):0};}
  getPerkOffers(){
    return Object.values(PERKS).filter(perk=>perk.cost).map(perk=>{const value=this.perkPreview(perk.id);return {...value,price:Math.round(value.cost*this.modifiers.shopDiscount),label:perk.name,maxed:value.level>=value.max};});
  }
  choosePerk(id){
    if(this.phase!=='choice'||!this.choices.some(value=>value.id===id))return false;
    this.applyPerk(id);this.choices=[];this.phase='intermission';this.timer=Math.max(4,this.timer);return true;
  }
  applyPerk(id){
    const perk=PERKS[id],level=this.perkLevels[id]||0;if(!perk||level>=perk.max)return false;
    if(!perk.effect)this.perkLevels[id]=level+1;
    if(id==='secondWind')this.secondWindCharges=1;
    this.emit({type:'perk-chosen',id,name:perk.name,level:this.perkLevels[id]||0,effect:perk.effect||null,value:perk.value??(id==='payday'?180+this.round*35:0),modifiers:this.modifiers});return true;
  }
  buyPerk(id,wallet){const preview=this.getPerkOffers().find(value=>value.id===id);if(!preview?.price||!wallet||!Number.isFinite(wallet.coins)||wallet.coins<preview.price||preview.maxed)return false;wallet.coins-=preview.price;this.applyPerk(id);this.emit({type:'perk-purchased',id,cost:preview.price});return true;}
  consumeSecondWind(){if(this.secondWindCharges<1)return false;this.secondWindCharges=0;this.secondWindRecoverAt=this.round+2;this.emit({type:'second-wind-consumed',rechargeRound:this.secondWindRecoverAt});return true;}
  activatePowerup(id){
    const config=POWERUPS[id];if(!config||this.phase==='dead'||this.phase==='ready')return false;
    if(config.duration){const previous=this.powers.get(id);this.powers.set(id,{id,time:Math.max(previous?.time||0,config.duration),duration:config.duration});}
    this.emit({type:'powerup-active',id,name:config.name,icon:config.icon,color:config.color,duration:config.duration,effect:config.effect,value:id==='nuke'?1200+this.round*30:id==='jackpot'?300+this.round*35:0});return true;
  }
  startEvent(id=null){
    if(this.event||this.phase!=='combat')return false;
    const available=Object.values(RUN_EVENTS).filter(value=>value.unlockRound<=this.round);
    const config=id?RUN_EVENTS[id]:available[Math.floor(this.random()*available.length)];
    if(!config||config.unlockRound>this.round)return false;
    this.event={config,time:config.duration};this.emit({type:'event-start',event:{...config},id:config.id,duration:config.duration});return true;
  }
  endEvent(){if(!this.event)return false;const id=this.event.config.id;this.event=null;this.emit({type:'event-end',id});return true;}
  get modifiers(){
    const levels=this.perkLevels,difficulty=this.difficultyConfig,chaos=this.chaosConfig,event=this.event?.config.modifiers||{};
    const momentum=Math.min(5,this.recentKills.length)*(levels.momentum||0)*.04;
    return {
      damage:(1+(levels.riskTaker||0)*.12)*(this.powers.has('doubleDamage')?2:1),
      fireRate:(1+momentum)*(this.powers.has('frenzy')?1.45:1),reloadTime:Math.max(.64,1-(levels.quickHands||0)*.12),
      moveSpeed:(1+(levels.lightweight||0)*.06)*(this.powers.has('frenzy')?1.18:1),
      criticalChance:(levels.deadeye||0)*.08,criticalMultiplier:1+(levels.deadeye||0)*.12,
      maxHealth:Math.max(.7,1+(levels.ironSkin||0)*.18-(levels.riskTaker||0)*.08),armor:(levels.ironSkin||0)*.04,
      reserveAmmo:1+(levels.ammoHoarder||0)*.25,killReload:(levels.recycle||0)*.05,headshotExplosion:(levels.headburst||0)*.25,
      secondWind:this.secondWindCharges,chainTargets:levels.conductor||0,pierce:levels.penetrator||0,elementalDamage:1+(levels.catalyst||0)*.15,
      dogDamage:1+(levels.bond||0)*.15,dogCooldown:Math.max(.79,1-(levels.bond||0)*.07),
      infiniteAmmo:this.powers.has('infiniteAmmo'),magnet:this.powers.has('magnet'),
      element:this.powers.has('overcharge')?['burn','chain','frost'][Math.floor(this.time*4)%3]:null,
      reward:difficulty.reward*chaos.reward*(event.reward||1)*this.mutators.reduce((value,item)=>value*(item.reward||1),1),
      xp:difficulty.xp*chaos.xp,lootChance:difficulty.lootChance*chaos.lootChance*(event.lootChance||1),
      lootQuality:difficulty.lootQuality+chaos.lootQuality,shopDiscount:event.shopDiscount||1,visibility:event.visibility||1,enemyAggression:event.aggression||1,
    };
  }
  getHUD(){return {
    round:this.round,phase:this.phase,remaining:this.remaining,kills:this.kills,target:this.target,queued:this.spawnQueue.length,alive:Math.max(0,this.spawned-this.kills),
    countdown:Math.ceil(this.timer),difficulty:this.difficulty,difficultyName:this.difficultyConfig.name,chaos:this.chaos,chaosName:this.chaosConfig.name,pressure:this.pressure,
    event:this.event?{id:this.event.config.id,name:this.event.config.name,time:Math.ceil(this.event.time),color:this.event.config.color}:null,
    activePowerups:[...this.powers.values()].map(value=>({...POWERUPS[value.id],time:Math.ceil(value.time),duration:value.duration})),
    perks:Object.entries(this.perkLevels).map(([id,level])=>({id,name:PERKS[id].name,icon:PERKS[id].icon,level,max:PERKS[id].max})),
    mutators:this.mutators.map(value=>({id:value.id,name:value.name,description:value.description})),choices:this.choices.map(value=>({...value})),
    stats:{totalKills:this.totalKills,headshots:this.headshots,bestCombo:this.bestCombo,time:this.time,completedRounds:this.completedRounds},
  };}
  end(){if(this.phase==='dead')return null;this.phase='dead';this.spawnQueue=[];this.choices=[];for(const id of this.powers.keys())this.emit({type:'powerup-expired',id});this.powers.clear();this.endEvent();const summary={runId:this.runId,round:this.round,completedRounds:this.completedRounds,kills:this.totalKills,headshots:this.headshots,bestCombo:this.bestCombo,time:this.time,difficulty:this.difficulty,chaos:this.chaos};this.emit({type:'run-ended',summary});return summary;}
}
