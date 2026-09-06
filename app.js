import * as THREE from 'three';
import {createExperience} from './experience.js';
import {GameAudio} from './systems/audio.js';
import {drawTacticalMap} from './systems/minimap.js';
import {createHillWorld} from './systems/hill-world.js';
import {Navigation} from './systems/navigation.js';
import {movePlayer} from './systems/player-movement.js';
import {createHero} from './systems/hero.js';
import {CombatSystem} from './systems/combat.js';
import {createEnemy,updateEnemyAI,disposeEnemy} from './systems/enemies.js';
import {BossSystem} from './systems/bosses.js';
import {EnemyProjectiles} from './systems/enemy-projectiles.js';
import {DogSystem} from './systems/dog.js';
import {RunDirector,runRandom} from './systems/run-director.js';
import {MetaProgression} from './systems/meta-progression.js';
import {rollWeapon} from './systems/weapon-rolls.js';
import {ATTACHMENTS,LOOT_WEAPONS} from './systems/loot-config.js';
import {LootWorld} from './systems/loot-world.js';
import {createShop} from './systems/shop.js';
import {createRunUI} from './systems/run-ui.js';

const $=id=>document.getElementById(id);
const ui=Object.fromEntries(['coins','cosmic','level','xpLabel','xpFill','treats','power','powerName','multiplier','regionName','objectiveTitle','objectiveText','objectiveProgress','objectiveFill','drawerCoins','upgradeList','missionList','toast','eventBanner','eventText','startScreen','barkCooldown','weatherIcon','health','healthFill','puppyCount','miniMap','actionHint','roundNumber','roundStatus','roundFill'].map(id=>[id,$(id)]));
const state={running:false,paused:false,coins:250,cosmic:0,treats:0,xp:0,level:1,power:1,multiplier:1,time:0,earned:0,region:'Largo da Chegada',weather:'sol',upgrades:{speed:1,jump:0,dash:0,bark:0,armor:0,regen:0,magnet:0,luck:0,dig:0,secret:0},missions:[]};
const upgrades=[
  {id:'speed',group:'MOVIMENTO',title:'Patas velozes',desc:'Mais velocidade entre as vielas.',base:95},
  {id:'jump',group:'MOVIMENTO',title:'Salto de telhado',desc:'Mais impulso para alcançar passagens.',base:125},
  {id:'dash',group:'MOVIMENTO',title:'Arrancada',desc:'Esquive com maior frequência.',base:145},
  {id:'bark',group:'COMBATE',title:'Latido sísmico',desc:'Abra espaço na horda ao redor.',base:155},
  {id:'armor',group:'DEFESA',title:'Coleira reforçada',desc:'Reduz o dano recebido.',base:160},
  {id:'regen',group:'DEFESA',title:'Segundo respiro',desc:'Recuperação gradual após receber dano.',base:190},
  {id:'magnet',group:'EXPLORAÇÃO',title:'Faro magnético',desc:'Alcance maior para recolher petiscos.',base:95},
  {id:'luck',group:'EXPLORAÇÃO',title:'Sorte salsicha',desc:'Mais petiscos nas recompensas.',base:160},
];
const player={pos:new THREE.Vector3(),velocity:new THREE.Vector3(),moveVelocity:new THREE.Vector3(),thirdPerson:false,cameraYaw:0,cameraPitch:-.045,dir:0,onGround:true,groundY:0,health:100,maxHealth:100,shield:0,shieldTime:0,damageCooldown:0,dash:0,dashCooldown:0,barkCooldown:0,firing:0,aiming:false,aimHeld:false,downed:false,downTimer:0};
const roundState={round:1,kills:0,target:0,active:false,cooldown:4};
const keys={},enemies=[],colliders=[],props=[],usedInteractions=new Set();
const seed=crypto.getRandomValues(new Uint32Array(1))[0],random=runRandom(seed);
const meta=new MetaProgression();
let scene,camera,renderer,world,navigation,hero,dog,barkView,combat,companion,bosses,loot,shop,experience,runUI,director,enemyProjectiles;
let audioContext,soundscape,masterVolume=.5,bonuses=meta.getRunBonuses(),mapRange=26,uiClock=0,slowTime=0,roundDamage=0,damageWindow=0,damageRecent=0,ended=false,challenge=null,quest=null;
let sunlight,ambient,toastTimer,interactionFocus=null,lateChoice=null;
const timer=new THREE.Clock();
const alive=()=>enemies.filter(enemy=>!enemy.disabled);
const active=()=>state.running&&!state.paused&&!ended;
const modifiers=()=>({...director?.modifiers,reward:(director?.modifiers.reward||1)*(1+state.upgrades.luck*.12)});
const point=value=>new THREE.Vector3(value.x,value.y||0,value.z);
function toast(message){ui.toast.textContent=message;ui.toast.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>ui.toast.classList.remove('show'),3000);}
function initAudio(){if(!audioContext){const Context=window.AudioContext||window.webkitAudioContext;if(!Context)return;audioContext=new Context();soundscape=new GameAudio(audioContext);soundscape.setVolume(masterVolume);soundscape.setMix((experience?.settings.musicVolume??35)/100,(experience?.settings.effectsVolume??80)/100);}audioContext.resume?.();}
function playSound(type){soundscape?.play(type);}
function coins(amount){if(!Number.isFinite(amount))return;state.coins=Math.max(0,state.coins+Math.round(amount));if(amount>0){state.earned+=Math.round(amount);state.treats++;}experience?.reward(Math.round(amount));}
function gainXP(amount){state.xp+=Math.max(0,Math.round(amount||0));let needed=80+state.level*35;while(state.xp>=needed){state.xp-=needed;state.level++;needed=80+state.level*35;player.health=Math.min(player.maxHealth,player.health+8);playSound('level');}}

function setup(){
  renderer=new THREE.WebGLRenderer({canvas:$('game'),antialias:true,powerPreference:'high-performance'});
  renderer.setPixelRatio(Math.min(devicePixelRatio,1.7));renderer.setSize(innerWidth,innerHeight);renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.08;
  scene=new THREE.Scene();scene.background=new THREE.Color('#899b9b');scene.fog=new THREE.Fog('#899b9b',48,150);camera=new THREE.PerspectiveCamera(66,innerWidth/innerHeight,.08,230);scene.add(camera);
  ambient=new THREE.HemisphereLight('#e1e9dc','#4c5142',2.3);sunlight=new THREE.DirectionalLight('#ffe0af',2.5);sunlight.position.set(-24,54,-22);sunlight.castShadow=true;sunlight.shadow.mapSize.set(2048,2048);Object.assign(sunlight.shadow.camera,{left:-52,right:52,top:80,bottom:-80,far:170});sunlight.shadow.bias=-.0003;scene.add(ambient,sunlight);
  world=createHillWorld({scene,colliders,seed});player.pos.copy(world.spawn);navigation=new Navigation(colliders,{heightAt:world.heightAt});
  hero=createHero(scene,player,()=>experience?.portrait());dog=hero.root;barkView=new THREE.Group();camera.add(barkView);
  experience=createExperience({THREE,state,player,ui,keys,upgrades,scene,camera,renderer,dog,dogParts:hero.parts,barkView,roundState,solidColliders:colliders,objects:props,chaosBots:enemies,colossi:[],projectiles:[],
    bark,sniff,dig:interact,jump,dash,formPack:()=>companion.command(),renderUpgrades:()=>{shop?.setStation(nearInteraction()?.type==='forge'?'forge':null);shop?.render();},renderMissions:()=>runUI?.renderChallenges(),drawMiniMap,updateUI,initAudio,startMusic:()=>{initAudio();soundscape?.setActive(true);},playSound,dust:()=>{},showToast:toast,resize,prestige:()=>{},getBoss:()=>null,getCombat:()=>combat,getDog:()=>companion,getDirector:()=>director,startRun,onEndRun:finishRun,onMenu:()=>runUI?.renderMenu(),
    openInventory:()=>{shop.setStation(null);shop.openTab('inventory');experience.openDrawer('upgradeDrawer');},
    setShake:()=>{},setVolume:value=>{masterVolume=value;soundscape?.setVolume(value);},setAudioMix:(music,effects)=>soundscape?.setMix(music,effects),pauseMusic:()=>soundscape?.setActive(false),resumeMusic:()=>soundscape?.setActive(true)});
  combat=new CombatSystem({scene,camera,dog,player,colliders,props,enemies,getBoss:()=>null,getWorld:()=>world,settings:()=>experience.settings,active,time:()=>state.time,getAudio:()=>audioContext,getAudioEngine:()=>soundscape,getVolume:()=>masterVolume,getModifiers:modifiers,syncAim:()=>experience.updateCamera(0),toast,reward:value=>experience.reward(value),onKill:enemyKilled,onDamageDealt:amount=>damageRecent+=amount});
  enemyProjectiles=new EnemyProjectiles({scene,player,combat,hurtPlayer:hurt,active});
  companion=new DogSystem({scene,hero:dog,player,enemies,navigation,combat,toast,getLoot:()=>loot,getPlayerState:()=>player,revivePlayer:revive,grantShield:(amount,duration)=>{player.shield=Math.max(player.shield,amount);player.shieldTime=duration;},metaBonuses:bonuses});
  loot=new LootWorld({scene,player,combat,world,getDirector:()=>director,state,reward:coins,toast,onCollect:collectedLoot,getDog:()=>companion,random});
  shop=createShop({state,roundState,combat,dog:companion,legacyUpgrades:upgrades,buyLegacy:buy,toast,updateUI,getDirector:()=>director,getMeta:()=>meta,world});
  bosses=new BossSystem({scene,player,enemies,navigation,world,combat,onReward:bossReward,announce:(title,text)=>experience.announce('CONFRONTO ESPECIAL',title,text||''),audio:{play:playSound},getRound:()=>director?.round||1,getModifiers:()=>({health:(director?.difficultyConfig.health||1)*(director?.chaosConfig.health||1),damage:(director?.difficultyConfig.damage||1)*(director?.chaosConfig.damage||1),chaos:director?.chaos||0}),hurtPlayer:hurt});
  runUI=createRunUI({meta,getDirector:()=>director,experience,toast,onChoose:id=>{const accepted=director.choosePerk(id);if(accepted)refreshStats();return accepted;}});
  experience.bind();runUI.renderMenu();updateUI();resize();experience.portrait();
  $('mapZoomIn').onclick=()=>{mapRange=Math.max(16,mapRange-5);drawHudMap();};$('mapZoomOut').onclick=()=>{mapRange=Math.min(60,mapRange+5);drawHudMap();};
  $('mobileInteract')?.addEventListener('click',interact);animate();
}
function startRun(){
  bonuses=meta.getRunBonuses();meta.beginRun({runId:`${seed}:${Date.now()}`});
  director=new RunDirector({difficulty:$('difficultySelect')?.value||'normal',chaos:Number($('chaosSelect')?.value||0),seed,meta,runId:meta.runId,emit:runEvent});
  player.maxHealth=Math.round(100*bonuses.maxHealthMultiplier);player.health=player.maxHealth;
  if(bonuses.startingWeaponId!=='biscuit'){combat.arsenal.grant(bonuses.startingWeaponId);combat.arsenal.equip(bonuses.startingWeaponId);}
  const part=ATTACHMENTS[bonuses.startingAttachmentId];if(part){const stashId=combat.arsenal.addAttachment(part.id);if(stashId)combat.arsenal.equipAttachment(stashId);}
  for(const entry of combat.arsenal.inventory.values())entry.reserve=Math.min(combat.arsenal.stats(entry.id).maxReserve,Math.round(entry.reserve*bonuses.startingAmmoMultiplier));
  companion.training.healthMultiplier=bonuses.dogHealthMultiplier;companion.health=companion.training.stats().health;companion.skinColor=bonuses.skinColor;
  director.start();runUI.renderMenu();loot.spawnAmmo(world.spawn.clone().add(new THREE.Vector3(-2,0,5)));
}
function refreshStats(){
  const previous=player.maxHealth;player.maxHealth=Math.round(100*bonuses.maxHealthMultiplier*(director?.modifiers.maxHealth||1));
  player.health=Math.min(player.maxHealth,player.health+Math.max(0,player.maxHealth-previous));combat.arsenal.setModifiers(modifiers());
}
function runEvent(event){
  switch(event.type){
    case 'spawn':spawnEnemy(event);break;
    case 'round-start':roundDamage=0;roundState.round=event.round;experience.announce('A LIGA DO RUÍDO SE APROXIMA',`ROUND ${String(event.round).padStart(2,'0')}`,event.mutators?.map(m=>m.name).join(' · ')||'Explore. Arme-se. Sobreviva.');playSound('round-start');break;
    case 'kill':loot.spawnMoney(Math.round(event.reward*(1+state.upgrades.luck*.12)),point(event.position));gainXP(event.xp);if(event.heal)player.health=Math.min(player.maxHealth,player.health+event.heal);break;
    case 'loot-drop':loot.spawnWeapon(rollWeapon({round:event.round,difficulty:director.difficulty,chaos:director.chaos,quality:event.qualityBonus,seed:Math.floor(random()*1e9),metaUnlocks:bonuses.metaUnlocks}),point(event.position));break;
    case 'powerup-drop':loot.spawnPowerup(event.id,point(event.position));break;
    case 'supply-drop':loot.spawnAmmo(point(event.position));break;
    case 'round-complete':
      coins(event.reward);gainXP(event.xp);meta.record('roundComplete',{round:event.round,damageTaken:roundDamage});player.health=Math.min(player.maxHealth,player.health+12);slowTime=experience.settings.reduceMotion?0:.34;
      experience.announce('MORRO CONQUISTADO',`ROUND ${event.round} COMPLETO`,`+${event.reward} petiscos · Abra um baú ou visite a forja.`);playSound('round-complete');loot.spawnAmmo(player.pos.clone().add(new THREE.Vector3(1.5,0,2)));break;
    case 'perk-choice':lateChoice=event.choices;break;
    case 'perk-chosen':refreshStats();playSound('purchase');if(event.effect==='coins'||event.id==='payday')coins(event.value);if(event.effect==='ammo')combat.arsenal.addAmmo(.5);if(event.effect==='heal'){player.health=Math.min(player.maxHealth,player.health+60);companion.health=Math.min(companion.training.stats().health,companion.health+40);}break;
    case 'milestone':meta.award('milestone',event);break;
    case 'powerup-active':
      experience.announce('POWER-UP!',event.name,`${event.duration?`${event.duration}s · `:''}Sua build ganhou fôlego.`);playSound('powerup');
      if(event.effect==='coins')coins(event.value);
      if(event.effect==='nuke')for(const enemy of [...alive()])combat.damage(enemy,event.value,{source:'powerup',effect:'explosive'});
      break;
    case 'event-start':experience.announce('O MORRO MUDOU',event.event.name,event.event.description);playSound('event');if(event.id==='bossHunt')startWorldBoss();break;
    case 'world-boss':startWorldBoss();break;
    case 'perk-purchased':experience.reward(-event.cost);meta.record('purchase');break;
  }
}
function spawnEnemy(event){
  const angle=event.angle??random()*Math.PI*2,distance=event.distance||22;
  const desired=player.pos.clone().add(new THREE.Vector3(Math.sin(angle)*distance,0,Math.cos(angle)*distance));
  const candidates=world.spawnPoints.filter(p=>p.distanceTo(player.pos)>9&&p.distanceTo(player.pos)<48);
  candidates.sort((a,b)=>a.distanceToSquared(desired)-b.distanceToSquared(desired));
  const position=navigation.freePosition((event.position||candidates[0]||desired).clone(),.5);
  const enemy=createEnemy(scene,{x:position.x,y:position.y,z:position.z,type:event.enemyType||'grunt',round:director.round,seed:Math.floor(random()*1e7),stats:event.stats,elite:event.elite,modifiers:event.modifiers});
  enemy.roundEnemy=event.roundEnemy!==false;enemy.runSpawnId=event.spawnId;enemies.push(enemy);return enemy;
}
function enemyKilled(enemy,source,detail={}){
  director?.onKill(enemy,{...detail,source});
  if(source!=='self')meta.record('kill',{headshot:detail.headshot,source});
  if(player.downed&&player.secondWind&&source==='weapon')revive(.4);
  bosses?.onEnemyKilled?.(enemy);
}
function bossReward(reward){
  const position=reward.position||reward.enemy?.g?.position||bosses.activeBoss?.g?.position||player.pos;
  meta.award('boss',{...reward,round:director.round,bossId:reward.bossId||reward.id||'boss',encounterId:reward.encounterId||`boss:${state.time}`});
  loot.spawnWeapon(rollWeapon({round:director.round,rarity:'legendary',chaos:director.chaos,seed:Math.floor(random()*1e9),metaUnlocks:bonuses.metaUnlocks}),point(position));
  loot.spawnAttachment('shockcell',point(position).add(new THREE.Vector3(1,0,0)));coins(reward.coins||450+director.round*35);
  experience.announce('BOSS DERROTADO','O MORRO É SEU','Arma lendária · peça rara · fragmentos permanentes');playSound('boss-killed');
}
function startWorldBoss(){if(!bosses.activeBoss){const center=player.pos.clone();bosses.start({id:`invasion-${director.round}`,name:'Invasão da Liga',position:center,center,radius:14,gateIds:[],unlockRound:1,archetype:random()<.5?'conductor':'furnace'});}}
function collectedLoot(){/* LootWorld owns pickup sounds and currency exactly once. */}
function buy(id){const config=upgrades.find(u=>u.id===id),level=state.upgrades[id]||0;if(!config||level>=5)return;const price=Math.round(config.base*Math.pow(1.52,level));if(state.coins<price){toast('Faltam petiscos para esta melhoria.');return;}state.coins-=price;state.upgrades[id]++;experience.reward(-price);experience.markPurchased(id);playSound('purchase');meta.record('purchase');shop.render();updateUI();}
function jump(){if(!active()||!player.onGround||player.downed)return;player.velocity.y=9.2+state.upgrades.jump*.8;player.onGround=false;playSound('jump');}
function dash(){if(!active()||player.dashCooldown>0||player.downed)return;player.dash=.18;player.dashCooldown=Math.max(.28,1.05-state.upgrades.dash*.085);playSound('dash');}
function bark(){if(!active()||player.barkCooldown>0||player.downed)return;player.barkCooldown=Math.max(.7,2.1-state.upgrades.bark*.12);playSound('bark');const radius=3.4+state.upgrades.bark*.45;for(const enemy of alive())if(enemy.g.position.distanceTo(player.pos)<radius&&navigation.clearLine(player.pos,enemy.g.position,.1)){combat.damage(enemy,22+state.upgrades.bark*10,{source:'bark',effect:'kinetic'});enemy.stunTime=Math.max(enemy.stunTime||0,.55);}combat.effects.burst(player.pos.clone().add(new THREE.Vector3(0,.4,0)),'#c9e8d3',12,2);}
function sniff(){if(!active())return;const nearby=world.interactions.filter(i=>!usedInteractions.has(i.id)).sort((a,b)=>a.position.distanceToSquared(player.pos)-b.position.distanceToSquared(player.pos))[0];if(nearby)toast(`${nearby.name} · ${Math.round(nearby.position.distanceTo(player.pos))} m · M para ver o mapa`);playSound('sniff');}
function hurt(amount,from){
  if(!active()||player.downed||player.damageCooldown>0||player.dash>0)return;
  const damage=amount/(1+state.upgrades.armor*.18)*(1-(director?.modifiers.armor||0)),shield=Math.min(player.shield,damage);player.shield-=shield;player.health=Math.max(0,player.health-damage+shield);player.damageCooldown=.45;roundDamage+=damage-shield;director.onDamage(damage-shield);meta.record('damage',{amount:damage-shield});experience.damage();playSound('hurt');
  if(player.health<=0){player.secondWind=director.consumeSecondWind();const rescue=companion.onPlayerDowned();if(player.secondWind||rescue){player.downed=true;player.downTimer=12;experience.announce('AINDA DÁ TEMPO','ÚLTIMO FÔLEGO',player.secondWind?'Elimine um inimigo para levantar.':'Faro está vindo salvar você.');}else experience.endGame();}
}
function revive(fraction=.35){player.downed=false;player.health=Math.max(1,Math.round(player.maxHealth*fraction));player.damageCooldown=3;player.secondWind=false;toast('De pé! Mais um round.');playSound('powerup');}
function finishRun(){if(ended)return;ended=true;const summary=director?.end();meta.endRun({...summary,completedRound:director?.completedRounds||0,score:state.earned,chaos:director?.chaos||0});$('resultMeta').textContent=`${meta.state.shards} fragmentos guardados · recorde: round ${meta.state.stats.bestRound}`;}

function nearInteraction(){return world.interactions.filter(item=>!usedInteractions.has(item.id)&&!item.opened&&Math.abs(item.position.y-player.pos.y)<1.6&&item.position.distanceTo(player.pos)<3.15&&combat.hitWorld.lineOfSight(player.pos.clone().add(new THREE.Vector3(0,1.2,0)),item.position.clone().add(new THREE.Vector3(0,1.2,0)))).sort((a,b)=>a.position.distanceToSquared(player.pos)-b.position.distanceToSquared(player.pos))[0]||null;}
function interact(){
  if(!active()||player.downed)return;if(loot.interact())return;
  const item=nearInteraction();if(!item){toast('Aproxime-se de um baú, porta ou estação.');return;}
  if(director.round<(item.unlockRound||1)){toast(`Disponível no round ${item.unlockRound}.`);return;}
  if(item.type==='shop'||item.type==='forge'){shop.setStation(item.type==='forge'?'forge':null);shop.openTab(item.type==='forge'?'forge':'weapons');experience.openDrawer('upgradeDrawer');return;}
  if(state.coins<(item.cost||0)){toast(`Você precisa de ${item.cost} petiscos.`);return;}
  if(item.type!=='door'&&item.doorId&&world.doors.find(d=>d.id===item.doorId)?.closed){toast('Abra primeiro a passagem que protege este cofre.');return;}
  if(['challenge','quest'].includes(item.type)&&(challenge||quest)){toast('Conclua o objetivo atual antes de aceitar outro.');return;}
  coins(-(item.cost||0));usedInteractions.add(item.id);item.opened=true;
  if(item.type==='door'||item.type==='gate'){world.openDoor(item.id);meta.record('gate');toast('Atalho aberto. A horda também pode atravessar.');}
  else if(item.type==='challenge'){challenge={item,time:30,start:state.time,leash:14};experience.announce('RISCO × RECOMPENSA','SEGURE A POSIÇÃO','Sobreviva por 30 s perto do relé. O loot raro é seu.');for(let i=0;i<3;i++)spawnEnemy({enemyType:i?'runner':'tank',roundEnemy:false,stats:director.statsFor(i?'runner':'tank',[]),angle:random()*6.28,distance:15});}
  else if(item.type==='quest'){quest=item;toast('Entrega aceita. Leve a peça ao ponto marcado no mirante.');}
  else{const rarity=item.lootTier>=3?'epic':item.lootTier>=2?'rare':item.lootTier>=1?'uncommon':undefined;loot.spawnWeapon(rollWeapon({round:director.round,rarity,seed:Math.floor(random()*1e9),chaos:director.chaos,metaUnlocks:bonuses.metaUnlocks}),item.position.clone().add(new THREE.Vector3(0,0,1)));loot.spawnAmmo(item.position.clone().add(new THREE.Vector3(1,0,0)));meta.record('chest');playSound('loot');toast('Baú aberto. Compare o equipamento antes de recolher.');}
  if(item.mesh&&!['door','gate'].includes(item.type))item.mesh.scale.y=.65;
}
function updateExploration(dt){
  interactionFocus=nearInteraction();const item=interactionFocus;
  ui.actionHint.textContent=item?`F · ${item.name}${director.round<(item.unlockRound||1)?` · ROUND ${item.unlockRound}`:item.cost&& !['forge','shop'].includes(item.type)?` · ${item.cost} petiscos`:''}`:'';
  ui.actionHint.classList.toggle('show',Boolean(item)&&!loot.focusDrop());
  if(challenge){if(player.pos.distanceTo(challenge.item.position)>challenge.leash){toast('Você deixou o relé. Desafio encerrado.');challenge=null;}else{challenge.time-=dt;if(challenge.time<=0){const p=challenge.item.position;loot.spawnWeapon(rollWeapon({round:director.round,rarity:'epic',seed:Math.floor(random()*1e9)}),p);coins(250);meta.record('chest');toast('Relé protegido! Equipamento épico liberado.');challenge=null;}}}
  if(quest&&player.pos.distanceTo(quest.target)<3){coins(quest.reward||250);gainXP(120);loot.spawnAttachment('burst',player.pos.clone());toast('Entrega concluída! Receptor de rajada + 250 petiscos.');quest=null;}
  const event=director.event?.config?.id;
  const black=event==='blackout',moon=event==='redmoon';ambient.intensity=THREE.MathUtils.lerp(ambient.intensity,black?.8:2.3,dt*2);sunlight.intensity=THREE.MathUtils.lerp(sunlight.intensity,black?.35:moon?1.3:2.5,dt*2);scene.fog.color.lerp(new THREE.Color(black?'#2c3741':moon?'#805b63':'#899b9b'),dt);scene.background.copy(scene.fog.color);
}
function mapData(){return {player,colliders,enemies,collectibles:[],companion,ammo:[],round:director?.round||1,world,interactions:world.interactions.filter(i=>!usedInteractions.has(i.id)),bossZones:world.bossZones,quest};}
function drawMiniMap(){drawTacticalMap(ui.miniMap,mapData(),76);}
function drawHudMap(){drawTacticalMap($('hudMap'),mapData(),mapRange);}
function updateUI(){
  const hud=director?.getHUD();if(hud){Object.assign(roundState,{round:hud.round,kills:hud.kills,target:hud.target,active:hud.phase==='combat',cooldown:hud.countdown});ui.roundNumber.textContent=String(hud.round).padStart(2,'0');ui.roundStatus.textContent=hud.phase==='combat'?`${hud.remaining} RESTANTES`:hud.phase==='choice'?'ESCOLHA SUA BUILD':`${hud.phase==='preparation'?'PREPARE-SE':'RESPIRA'} · ${Math.ceil(hud.countdown)}s`;ui.roundFill.style.width=`${hud.target?hud.kills/hud.target*100:0}%`;runUI.update(hud);}
  state.region=world.district(player.pos);ui.regionName.textContent=state.region;ui.level.textContent=state.level;ui.xpFill.style.width=`${state.xp/(80+state.level*35)*100}%`;ui.xpLabel.textContent=`${state.xp} / ${80+state.level*35}`;ui.drawerCoins.textContent=state.coins.toLocaleString('pt-BR');ui.cosmic.textContent=meta.state.shards;ui.multiplier.textContent=`×${(director?.modifiers.reward||1).toFixed(1)}`;ui.puppyCount.textContent='Faro';ui.power.textContent=Math.round(combat.arsenal.stats().damage);ui.powerName.textContent='dano';
  $('maxHealth').textContent=player.maxHealth;$('shieldStatus').textContent=player.shield>0?`+${Math.ceil(player.shield)} escudo`:player.downed?`${Math.ceil(player.downTimer)}s para levantar`:'';
  ui.objectiveTitle.textContent=challenge?'Segure o relé':quest?'Entrega no Mirante':director?.round>=5?'Desafie o boss':'Abra caminho pelo morro';ui.objectiveText.textContent=challenge?`${Math.ceil(challenge.time)}s · permaneça no raio de 14m`:quest?'Leve a peça até a parte alta do mapa.':'Explore os baús, use a forja e abra os atalhos. As estrelas no mapa indicam bosses.';ui.objectiveProgress.textContent=state.region;ui.objectiveFill.style.width=challenge?`${(1-challenge.time/30)*100}%`:'0%';
  for(const event of meta.drainNotifications()){toast(event.kind==='shards'?`+${event.amount} fragmentos · ${event.name}`:`Desbloqueado: ${event.name}`);playSound('unlock');}
  drawHudMap();if(!ui.miniMap.closest('[hidden]'))drawMiniMap();
}
function resize(){camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);}
function animate(){
  requestAnimationFrame(animate);const raw=Math.min(timer.getDelta(),.05);
  if(active()){
    const dt=raw*(slowTime>0?.32:1);slowTime=Math.max(0,slowTime-raw);state.time+=dt;
    navigation.beginFrame();
    movePlayer(player,dt,{keys,world,navigation,upgrades:state.upgrades,modifiers:director.modifiers,bonuses});
    if(!player.downed&&player.damageCooldown===0)player.health=Math.min(player.maxHealth,player.health+state.upgrades.regen*.38*dt);
    hero.update(dt,state.time,player.moveVelocity.length());experience.updateCamera(dt);combat.beginFrame(dt);experience.tick(dt);
    for(const enemy of enemies)updateEnemyAI(enemy,{dt,time:state.time,player,companion,peers:enemies,camera,navigation,aggression:director.modifiers.enemyAggression,hurtPlayer:hurt,hurtDog:amount=>companion.hurt(amount),fireRanged:(enemy,target)=>enemyProjectiles.fire(enemy,target),combat,spawn:(type,position)=>spawnEnemy({enemyType:type,roundEnemy:false,position})});
    enemyProjectiles.update(dt);bosses.update(dt,state.time);companion.update(dt,state.time);combat.update(dt);loot.update(dt,state.time);updateExploration(dt);
    for(let i=enemies.length-1;i>=0;i--)if(enemies[i].disabled&&(enemies[i].deathTime||0)>2){disposeEnemy(enemies[i]);enemies.splice(i,1);}
    damageWindow+=dt;if(damageWindow>3){damageWindow=0;damageRecent*=.3;}
    const current=combat.arsenal.current,stats=combat.arsenal.stats();director.update(dt,{healthRatio:player.health/player.maxHealth,ammoRatio:(current.magazine+current.reserve)/(stats.magazineSize+stats.maxReserve),enemiesAlive:alive().length,dps:damageRecent/3,position:player.pos,heading:player.cameraYaw});
    if(player.downed){player.downTimer-=dt;if(player.downTimer<=0||(!player.secondWind&&!companion.rescuing))experience.endGame();}
    if(lateChoice&&slowTime<=0){const choices=lateChoice;lateChoice=null;runUI.showChoices(choices);}
    soundscape?.update(dt,{moving:player.moveVelocity.length()>1,onGround:player.onGround,enemies:alive().filter(e=>e.g.position.distanceTo(player.pos)<20).length,round:director.round,boss:bosses.activeBoss,event:director.event?.config,healthRatio:player.health/player.maxHealth,pressure:director.pressure});
    uiClock+=dt;if(uiClock>.2){uiClock=0;updateUI();}
  }else{experience.tick(raw);combat.view.root.visible=false;}
  renderer.render(scene,camera);
}
setup();
