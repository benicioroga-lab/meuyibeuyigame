import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {RunDirector,runRandom} from '../systems/run-director.js';
import {RUN_BALANCE} from '../systems/run-config.js';
import {CombatSystem} from '../systems/combat.js';
import {createEnemy,updateEnemyAI,disposeEnemy} from '../systems/enemies.js';
import {createHillWorld} from '../systems/hill-world.js';
import {Navigation} from '../systems/navigation.js';
import {LootWorld} from '../systems/loot-world.js';
import {BossSystem} from '../systems/bosses.js';
import {MetaProgression} from '../systems/meta-progression.js';
import {rollWeapon} from '../systems/weapon-rolls.js';

// Only rendering and user input are absent. Map geometry, visible hit meshes, paths,
// spawn director, weapons, drops, encounter phases and persistence use their real modules.
function fixture({seed=31,difficulty='normal',chaos=0}={}){
  const random=runRandom(seed),scene=new THREE.Scene(),colliders=[],enemies=[],events=[],state={coins:250,xp:0},collected=[],bossRewards=[];
  const world=createHillWorld({scene,colliders,seed}),navigation=new Navigation(colliders,{heightAt:world.heightAt}),camera=new THREE.PerspectiveCamera(66,16/9,.05,200),hero=new THREE.Group();scene.add(camera,hero);
  const player={pos:world.spawn.clone(),moveVelocity:new THREE.Vector3(),velocity:new THREE.Vector3(),cameraYaw:0,aiming:true,thirdPerson:false,health:100,maxHealth:100,onGround:true,damageCooldown:0};
  const stored=new Map(),storage={getItem:key=>stored.get(key)||null,setItem:(key,value)=>stored.set(key,value)},meta=new MetaProgression({storage,runId:`integration:${seed}`});
  let time=0,director,loot,bosses,paused=false,damageTaken=0,damageThisWindow=0;
  const combat=new CombatSystem({scene,camera,dog:hero,player,enemies,props:[],colliders,getWorld:()=>world,getBoss:()=>bosses?.activeBoss,settings:()=>({reduceMotion:true,damageNumbers:false}),active:()=>!paused&&player.health>0,time:()=>time,getAudio:()=>null,getVolume:()=>0,getModifiers:()=>director?.modifiers||{},toast(){},reward(){},onDamageDealt:amount=>damageThisWindow+=amount,
    onKill(enemy,source,detail){director.onKill(enemy,{...detail,source});if(source!=='self')meta.record('kill',{headshot:detail.headshot,source});bosses?.onEnemyKilled(enemy);}});
  combat.arsenal.random=random;
  function spawn(event){
    const desired=player.pos.clone().add(new THREE.Vector3(Math.sin(event.angle||0)*(event.distance||20),0,Math.cos(event.angle||0)*(event.distance||20)));
    const choices=world.spawnPoints.filter(p=>p.distanceTo(player.pos)>9&&p.distanceTo(player.pos)<48).sort((a,b)=>a.distanceToSquared(desired)-b.distanceToSquared(desired));
    const position=navigation.freePosition((event.position||choices[0]||desired).clone(),.5);
    const enemy=createEnemy(scene,{x:position.x,y:position.y,z:position.z,type:event.enemyType,round:event.round,stats:event.stats,elite:event.elite,seed:Math.floor(random()*1e6),roundEnemy:event.roundEnemy!==false});enemy.runSpawnId=event.spawnId;enemies.push(enemy);return enemy;
  }
  function emit(event){
    events.push({type:event.type,round:event.round,reward:event.reward,source:event.source});
    if(event.type==='spawn')spawn(event);
    if(event.type==='kill'){loot.spawnMoney(event.reward,event.position);state.xp+=event.xp;}
    if(event.type==='loot-drop')loot.spawnWeapon(rollWeapon({round:event.round,seed:Math.floor(random()*1e9),difficulty,chaos,quality:event.qualityBonus}),event.position);
    if(event.type==='powerup-drop')loot.spawnPowerup(event.id,event.position);
    if(event.type==='supply-drop')loot.spawnAmmo(event.position);
    if(event.type==='round-complete'){state.coins+=event.reward;state.xp+=event.xp;player.health=Math.min(player.maxHealth,player.health+12);loot.spawnAmmo(player.pos.clone().add(new THREE.Vector3(0,0,1)));meta.record('roundComplete',{round:event.round,damageTaken});}
    if(event.type==='milestone')meta.award('milestone',event);
  }
  director=new RunDirector({seed,difficulty,chaos,runId:meta.runId,emit});
  loot=new LootWorld({scene,player,combat,state,world,getDirector:()=>director,random,document:null,onCollect:drop=>collected.push({type:drop.type,amount:drop.amount,id:drop.id})});
  function hurt(amount){if(player.damageCooldown>0||player.health<=0)return;player.health=Math.max(0,player.health-amount);player.damageCooldown=.45;damageTaken+=amount;director.onDamage(amount);}
  bosses=new BossSystem({scene,player,enemies,navigation,world,combat,getRound:()=>director.round,getModifiers:()=>({health:director.difficultyConfig.health,damage:director.difficultyConfig.damage,chaos}),hurtPlayer:hurt,onReward(reward){bossRewards.push(reward);meta.award('boss',{...reward,encounterId:`${meta.runId}:${reward.zoneId}`});loot.spawnWeapon(rollWeapon({round:director.round,seed:Math.floor(random()*1e9),rarity:reward.rarity}),reward.position);state.coins+=reward.coins;}});
  function aim(enemy,headshot=true){camera.position.copy(player.pos).add(new THREE.Vector3(0,1.2,0));const at=enemy.g.position.clone().add(new THREE.Vector3(0,enemy.config.scale*(headshot?1.77:1.18),0));camera.lookAt(at);camera.updateMatrixWorld(true);player.cameraYaw=Math.atan2(at.x-player.pos.x,at.z-player.pos.z);}
  function step(dt,{runAI=true,runBoss=true}={}){
    if(paused||player.health<=0)return;time+=dt;player.damageCooldown=Math.max(0,player.damageCooldown-dt);combat.beginFrame(dt);
    if(runAI)for(const enemy of enemies)updateEnemyAI(enemy,{dt,time,player,navigation,peers:enemies,camera,combat,hurtPlayer:hurt,hurtDog(){}});
    if(runBoss)bosses.update(dt,time);combat.update(dt);loot.update(dt,time);
    for(let i=enemies.length-1;i>=0;i--)if(enemies[i].disabled&&enemies[i].deathTime>2){disposeEnemy(enemies[i]);enemies.splice(i,1);}
    const entry=combat.arsenal.current,stats=combat.arsenal.stats();director.update(dt,{healthRatio:player.health/player.maxHealth,ammoRatio:(entry.magazine+entry.reserve)/(stats.magazineSize+stats.maxReserve),enemiesAlive:enemies.filter(e=>!e.disabled).length,dps:damageThisWindow/3,heading:player.cameraYaw});damageThisWindow*=Math.exp(-dt/3);
  }
  function dispose(){bosses.dispose();for(const enemy of enemies)disposeEnemy(enemy);enemies.length=0;loot.dispose();combat.dispose();world.dispose();scene.remove(camera,hero);}
  return {scene,colliders,enemies,events,state,collected,bossRewards,world,navigation,camera,hero,player,meta,storage,stored,combat,director,loot,bosses,spawn,aim,step,dispose,get time(){return time;},setPaused:value=>paused=value};
}

test('a full directed wave pays money on collection, emits one round reward and rejects duplicate kill callbacks',()=>{
  const f=fixture();f.director.start();let enemyRewards=0;
  for(let frame=0;frame<1200&&f.director.completedRounds===0;frame++){
    f.step(.05,{runAI:false,runBoss:false});
    for(const enemy of f.enemies.filter(e=>!e.disabled)){
      const coins=f.state.coins,roundBefore=f.director.completedRounds;f.combat.damage(enemy,10000,{source:'weapon',weaponId:f.combat.arsenal.currentId});enemyRewards+=enemy.config.reward;
      assert.equal(f.director.onKill(enemy,{source:'weapon'}),false);assert.equal(f.state.coins,coins+(f.director.completedRounds>roundBefore?145:0),'kills must not silently grant uncollected money');
    }
  }
  assert.equal(f.director.completedRounds,1);assert.equal(f.events.filter(e=>e.type==='round-complete').length,1);assert.equal(f.state.coins,395);assert.ok(f.state.xp>0);
  for(const drop of [...f.loot.drops].filter(d=>d.type==='money')){f.player.pos.copy(drop.position);assert.equal(f.loot.collect(drop),true);assert.equal(f.loot.collect(drop),false);}
  assert.equal(f.state.coins,395+enemyRewards);assert.equal(f.director.completeRound(),false);f.dispose();assert.equal(f.scene.children.length,0);assert.equal(f.colliders.length,0);
});

test('real ramp combat and tunnel loot respect the same vertical geometry used by navigation',()=>{
  const f=fixture(),enemy=f.spawn({enemyType:'grunt',round:1,roundEnemy:false,position:new THREE.Vector3(20,6,4.3)});
  f.player.pos.set(20,0,-16);f.aim(enemy);const preview=f.combat.preview();assert.equal(preview.hits[0]?.entity,enemy);assert.equal(f.combat.fire(),true);assert.ok(enemy.health<enemy.maxHealth);
  f.player.pos.set(0,0,9);const roofMoney=f.loot.spawnMoney(50,new THREE.Vector3(0,6,9)),tunnelMoney=f.loot.spawnMoney(25,new THREE.Vector3(0,0,9));assert.equal(f.loot.collect(roofMoney),false);assert.equal(f.loot.collect(tunnelMoney),true);
  assert.ok(Math.abs(f.combat.hitWorld.surfaces(new THREE.Vector3(0,1,9),new THREE.Vector3(0,1,0),10).point.y-3.4)<1e-8);f.dispose();
});

test('boss zones share gun hit detection, advance phases, reopen their gates and award one legendary plus permanent currency',()=>{
  const f=fixture();f.director.start();f.director.startRound(5);const zone=f.world.bossZones[0];f.player.pos.copy(zone.position||zone.center);
  assert.equal(f.bosses.start(zone),true);const boss=f.bosses.activeBoss,gate=f.world.doors.find(d=>d.id===zone.gateId);assert.equal(gate.closed,true);
  f.aim(boss);assert.equal(f.combat.preview().hits.filter(hit=>hit.entity===boss).length,1);const full=boss.health;assert.equal(f.combat.fire(),true);assert.ok(boss.health<full);
  f.combat.damage(boss,boss.maxHealth*.33/.96,{source:'weapon'});f.bosses.update(.05);assert.equal(boss.phase,2);
  f.combat.damage(boss,boss.maxHealth*.35/.96,{source:'weapon'});f.bosses.update(.05);assert.equal(boss.phase,3);
  f.combat.damage(boss,1e6,{source:'weapon',weaponId:f.combat.arsenal.currentId});f.bosses.onEnemyKilled(boss);f.bosses.update(.1);
  assert.equal(f.bossRewards.length,1);assert.equal(gate.closed,false);assert.equal(f.director.kills,0);assert.equal(f.meta.state.stats.bosses,1);assert.ok(f.meta.state.shards>0);
  const drop=f.loot.drops.find(d=>d.type==='weapon');assert.equal(drop.roll.rarity,'legendary');f.player.pos.copy(drop.position);assert.equal(f.loot.collect(drop,{equip:true}),true);assert.equal(f.combat.arsenal.current.roll.rarity,'legendary');
  assert.equal(f.bosses.start(zone),false,'boss reward cannot be farmed by stepping across the gate');f.dispose();
});

test('pausing the integrated run freezes reload, drops, enemy navigation and director clocks',()=>{
  const f=fixture();f.director.start();f.step(1);f.combat.arsenal.current.magazine=0;f.combat.reload();const drop=f.loot.spawnAmmo(f.player.pos.clone().add(new THREE.Vector3(0,0,8))),enemy=f.spawn({enemyType:'runner',round:1,roundEnemy:false,position:f.player.pos.clone().add(new THREE.Vector3(0,0,12))});
  const snapshot=[f.time,f.director.time,f.combat.arsenal.reloadState.remaining,drop.age,...enemy.g.position.toArray()];f.setPaused(true);f.step(10);assert.deepEqual([f.time,f.director.time,f.combat.arsenal.reloadState.remaining,drop.age,...enemy.g.position.toArray()],snapshot);
  f.setPaused(false);f.step(.1);assert.ok(f.combat.arsenal.reloadState.remaining<snapshot[2]);assert.ok(drop.age>0);f.dispose();
});

test('five simulated minutes connect horde navigation, finite ammo, upgrades, loot and cleanup with bounded resources',t=>{
  const f=fixture({seed:19,difficulty:'easy'});f.director.start();let peakActors=0,peakEffects=0,peakLoot=0,shots=0;
  for(let frame=0;frame<3000;frame++){
    if(f.director.phase==='choice')f.director.choosePerk(f.director.choices[0].id);
    // A stationary aim policy is intentionally stronger than manual play; no damage or ammo values are overridden.
    const enemy=f.enemies.filter(e=>!e.disabled).sort((a,b)=>a.g.position.distanceToSquared(f.player.pos)-b.g.position.distanceToSquared(f.player.pos))[0];
    if(enemy){f.aim(enemy);if(f.combat.fire())shots++;}
    const arsenal=f.combat.arsenal,entry=arsenal.current,stats=arsenal.stats();
    if(entry.reserve<stats.magazineSize&&f.state.coins>=35+f.director.round*3)arsenal.refill(f.state,f.director.round);
    if(f.director.round>=2&&!arsenal.inventory.has('boardwalk')&&f.state.coins>=420)arsenal.buy('boardwalk',f.state,f.director.round);
    if(f.director.round>=4&&!arsenal.inventory.has('hammer')&&f.state.coins>=950)arsenal.buy('hammer',f.state,f.director.round);
    f.step(.1);
    peakActors=Math.max(peakActors,f.enemies.length);peakEffects=Math.max(peakEffects,f.combat.effects.items.length);peakLoot=Math.max(peakLoot,f.loot.drops.length);
    for(const item of arsenal.inventory.values()){const config=arsenal.stats(item.id);assert.ok(item.magazine>=0&&item.magazine<=config.magazineSize);assert.ok(item.reserve>=0&&item.reserve<=config.maxReserve);}
    for(const e of f.enemies){assert.ok(Number.isFinite(e.health));assert.ok(e.health>=0&&e.health<=e.maxHealth);assert.ok(e.g.position.toArray().every(Number.isFinite));assert.ok(e.config.speed<=e.config.maxSpeed);}
    if(f.player.health<=0)break;
  }
  assert.ok(f.time>=299.9,`simulation ended at ${f.time.toFixed(1)}s, round ${f.director.round}`);assert.ok(f.director.completedRounds>=3,`completed ${f.director.completedRounds} rounds`);assert.ok(shots>100);
  assert.ok(peakActors<=RUN_BALANCE.maxConcurrent+16);assert.ok(peakEffects<=140);assert.ok(peakLoot<=60);assert.ok(f.state.coins>=0);assert.ok(f.combat.arsenal.inventory.size>1);
  t.diagnostic(`${f.time.toFixed(1)}s; ${f.director.completedRounds} rounds; ${shots} shots; peaks: ${peakActors} actors, ${peakEffects} effects, ${peakLoot} drops`);
  f.director.end();f.dispose();assert.equal(f.scene.children.length,0);assert.equal(f.colliders.length,0);assert.equal(f.combat.effects.items.length,0);assert.equal(f.loot.drops.length,0);
});
