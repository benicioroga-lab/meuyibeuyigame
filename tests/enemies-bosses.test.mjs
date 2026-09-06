import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {ENEMY_CONFIG,enemyStats,eliteModifiers,FACTION} from '../systems/enemy-config.js';
import {createEnemy,updateEnemyAI,animateEnemy,disposeEnemy} from '../systems/enemies.js';
import {BossSystem,bossPhase,bossStats} from '../systems/bosses.js';
import {createHillWorld} from '../systems/hill-world.js';
import {Navigation} from '../systems/navigation.js';

function arena(){
  const scene=new THREE.Scene(),player={pos:new THREE.Vector3(0,0,0),health:100},enemies=[],damage=[],gates=[],rewards=[],events=[],effects=[];
  const navigation={heightAt:()=>0,freePosition:position=>position,clearLine:()=>true,move(enemy,target,speed,dt){const movement=target.clone().sub(enemy.g.position).setY(0),distance=movement.length();if(distance)movement.multiplyScalar(Math.min(speed*dt,distance)/distance);enemy.g.position.add(movement);enemy.velocity.copy(movement).multiplyScalar(1/dt);enemy.lastMoveSpeed=speed;}};
  const combat={game:{camera:new THREE.PerspectiveCamera()},hitWorld:{lineOfSight:()=>true},effects:{nova:(...args)=>effects.push(args),burst(){},sound(){},beam(){}},damage(enemy,amount,options){enemy.health=Math.max(0,enemy.health-amount);if(!enemy.health)enemy.disabled=enemy.dead=true;events.push(['damage',options]);}};
  const world={bossZones:[{id:'summit',position:new THREE.Vector3(0,0,0),radius:10,unlockRound:5,archetype:'conductor',gateId:'summit-gate'}],setGate:(id,closed)=>gates.push([id,closed])};
  const spawn=(type,options={})=>{const enemy=createEnemy(scene,{x:0,z:8,type,seed:enemies.length,roundEnemy:true,...options});enemies.push(enemy);return enemy;};
  const context={dt:.05,player,navigation,peers:enemies,camera:combat.game.camera,combat,hurtPlayer:(amount)=>damage.push(amount),hurtDog(){},fireRanged:enemy=>events.push(['ranged',enemy]),emit:(event,payload)=>events.push([event,payload])};
  return {scene,player,enemies,damage,gates,rewards,events,effects,navigation,combat,world,spawn,context};
}

test('each faction class has region-specific visible hit meshes and strictly capped speed',()=>{
  const f=arena();
  for(const type of Object.keys(ENEMY_CONFIG)){
    const enemy=f.spawn(type),zones=new Set(enemy.hitMeshes.map(mesh=>mesh.userData.zone));
    assert.equal(enemy.faction,FACTION.id);for(const zone of ['head','body','arm','leg'])assert.ok(zones.has(zone),`${type}: ${zone}`);
    for(const round of [1,30,100,1000000]){const stats=enemyStats(type,round);assert.ok(stats.speed<=stats.maxSpeed);assert.ok(Number.isFinite(stats.hp));assert.ok(stats.hp<ENEMY_CONFIG[type].hp*2.6);}
    disposeEnemy(enemy);disposeEnemy(enemy);assert.equal(enemy.g.parent,null);
  }
});

test('shield health aliases stay in sync and the shield disappears after breaking',()=>{
  const f=arena(),enemy=f.spawn('shield');assert.ok(enemy.hitMeshes.some(mesh=>mesh.userData.zone==='shield'));
  enemy.shieldHealth-=30;assert.equal(enemy.shield.health,enemy.maxShieldHealth-30);
  enemy.shield.health=0;animateEnemy(enemy,.05,f.context.camera,f.navigation);assert.equal(enemy.shieldBroken,true);assert.equal(enemy.shield.mesh.visible,false);disposeEnemy(enemy);
});

test('berserk, frenzy and support buffs never bypass a class speed cap',()=>{
  const f=arena(),enemy=f.spawn('berserker',{round:100,elite:'frenzied'});enemy.health=1;enemy.speedBuffTime=3;
  for(let i=0;i<20;i++){updateEnemyAI(enemy,{...f.context,time:i*.05});assert.ok((enemy.lastMoveSpeed||0)<=enemy.config.maxSpeed);}
  assert.equal(eliteModifiers(12,6).length,6);assert.equal(new Set(eliteModifiers(12,6).map(m=>m.id)).size,6);disposeEnemy(enemy);
});

test('brute attack warns before damage and the player can leave its impact area',()=>{
  const f=arena(),enemy=f.spawn('brute',{z:1});enemy.attackCooldown=0;
  updateEnemyAI(enemy,f.context);assert.equal(f.damage.length,0);assert.equal(enemy.pendingAttack.kind,'melee');assert.equal(enemy.warning.visible,true);
  f.player.pos.z=12;for(let i=0;i<22;i++)updateEnemyAI(enemy,{...f.context,time:i*.05});assert.equal(f.damage.length,0);disposeEnemy(enemy);
});

test('exploder has a readable fuse, explodes once and records self destruction',()=>{
  const f=arena(),enemy=f.spawn('exploder',{z:1});enemy.attackCooldown=0;
  updateEnemyAI(enemy,f.context);assert.equal(f.damage.length,0);assert.equal(enemy.pendingAttack.kind,'explode');
  for(let i=0;i<50;i++)updateEnemyAI(enemy,{...f.context,time:i*.05});
  assert.equal(enemy.disabled,true);assert.equal(f.damage.length,1);assert.equal(f.events.filter(([event])=>event==='enemy-explosion').length,1);assert.ok(f.events.some(([event,payload])=>event==='damage'&&payload.source==='self'));disposeEnemy(enemy);
});

test('support heals only nearby visible allies, has a cooldown, and cannot resurrect',()=>{
  const f=arena(),support=f.spawn('support'),ally=f.spawn('grunt',{x:2}),dead=f.spawn('grunt',{x:3}),far=f.spawn('grunt',{x:30});
  support.health-=20;ally.health-=20;dead.disabled=true;dead.health=0;far.health=2;support.supportClock=0;
  updateEnemyAI(support,f.context);const healed=ally.health;assert.ok(healed>22);assert.equal(support.health,support.maxHealth-20);assert.equal(dead.health,0);assert.equal(far.health,2);
  updateEnemyAI(support,f.context);assert.equal(ally.health,healed);assert.ok(ally.damageBuffTime>0);
  for(const enemy of f.enemies)disposeEnemy(enemy);
});

test('elemental elites warn before their area attack and fire patches are visible and bounded',()=>{
  for(const modifier of ['fire','shock','frost']){
    const f=arena(),enemy=f.spawn('grunt',{z:2,elite:modifier});enemy.eliteClock=0;
    updateEnemyAI(enemy,f.context);assert.equal(enemy.pendingAttack.kind,`elite-${modifier}`);assert.equal(enemy.warning.visible,true);assert.equal(f.damage.length,0);
    for(let i=0;i<20;i++)updateEnemyAI(enemy,{...f.context,time:i*.05});assert.ok(f.damage.length>0);
    if(modifier==='fire'){assert.equal(enemy.hazards.length,1);assert.equal(enemy.hazards[0].mesh.parent,f.scene);for(let i=0;i<60;i++)updateEnemyAI(enemy,{...f.context,time:1+i*.05});assert.equal(enemy.hazards.length,0);}
    if(modifier==='frost')assert.ok(f.player.slowTime>0);
    disposeEnemy(enemy);assert.equal(enemy.hazards.length,0);
  }
});

test('a dog decoy redirects pursuit temporarily and expires normally',()=>{
  const f=arena(),enemy=f.spawn('grunt',{z:8}),companion={health:70,g:new THREE.Group()};companion.g.position.set(10,0,8);enemy.tauntTarget=companion;enemy.tauntTime=.5;
  updateEnemyAI(enemy,{...f.context,companion});assert.ok(enemy.g.position.x>0);assert.ok(enemy.tauntTime>0);
  for(let i=0;i<20;i++)updateEnemyAI(enemy,{...f.context,companion});assert.equal(enemy.tauntTime,0);assert.ok(enemy.g.position.z<8);disposeEnemy(enemy);
});

test('three death silhouettes and slope-aware gait stay finite during a long actor simulation',()=>{
  const f=arena(),poses=[];
  for(let seed=0;seed<3;seed++){const e=f.spawn('runner',{seed});e.disabled=true;animateEnemy(e,.5,f.context.camera,f.navigation);poses.push([e.rig.rotation.x,e.rig.rotation.z]);disposeEnemy(e);}
  assert.equal(new Set(poses.map(String)).size,3);
  const enemy=f.spawn('assassin'),slopes={...f.navigation,heightAt:(x,z)=>Math.sin(x*.1)*.1};
  for(let i=0;i<2400;i++){const time=i/30;f.player.pos.set(Math.sin(time*.5)*8,0,Math.cos(time*.5)*8);updateEnemyAI(enemy,{...f.context,dt:1/30,time,navigation:slopes});for(const value of [enemy.g.position.x,enemy.g.position.y,enemy.g.position.z,enemy.rig.rotation.x,enemy.rig.rotation.z])assert.ok(Number.isFinite(value));}
  disposeEnemy(enemy);
});

test('boss zones lock only after their round gate and issue one meaningful reward',()=>{
  const f=arena();let round=4;const system=new BossSystem({...f,getRound:()=>round,onReward:reward=>f.rewards.push(reward),hurtPlayer:amount=>f.damage.push(amount)});
  assert.equal(system.start('summit'),false);round=5;assert.equal(system.start('summit'),true);assert.deepEqual(f.gates,[['summit-gate',true]]);
  const boss=system.getBoss();assert.ok(f.enemies.includes(boss));assert.equal(boss.boss,true);assert.equal(boss.bossManaged,true);
  boss.health=0;boss.disabled=true;system.onEnemyKilled(boss);system.onEnemyKilled(boss);system.update(.1);assert.equal(f.rewards.length,1);assert.equal(f.rewards[0].rarity,'legendary');assert.ok(f.rewards[0].permanentCurrency>0);assert.deepEqual(f.gates.at(-1),['summit-gate',false]);assert.equal(system.start('summit'),false);
  round=15;assert.equal(system.start('summit'),true);system.dispose();assert.equal(system.getBoss(),null);assert.deepEqual(f.gates.at(-1),['summit-gate',false]);for(const enemy of f.enemies)disposeEnemy(enemy);
});

test('boss phases transition exactly at 70 and 35 percent and clear stale attacks',()=>{
  const f=arena(),system=new BossSystem({...f,getRound:()=>5});system.start('summit');const boss=system.getBoss();
  assert.equal(bossPhase(71,100),1);assert.equal(bossPhase(70,100),2);assert.equal(bossPhase(35,100),3);
  system.createWarning('mortar',f.player.pos.clone(),2,1,10);boss.health=boss.maxHealth*.7;system.update(.05);assert.equal(boss.phase,2);assert.equal(system.telegraphs.length,0);
  boss.health=boss.maxHealth*.35;system.update(.05);assert.equal(boss.phase,3);assert.ok(boss.bossCooldown>1);system.dispose();for(const enemy of f.enemies)disposeEnemy(enemy);
});

test('a distant world-boss hunt never traps the player behind gates or attacks remotely',()=>{
  const f=arena(),system=new BossSystem({...f,getRound:()=>30});f.player.pos.set(0,0,-60);
  assert.equal(system.start('summit',{worldBoss:true}),true);assert.equal(system.activeBoss.worldBoss,true);assert.equal(f.gates.length,0);
  for(let i=0;i<300;i++)system.update(1/30,i/30);assert.equal(system.telegraphs.length,0);assert.equal(system.activeBoss.attackIndex,0);
  f.player.pos.set(0,0,0);for(let i=0;i<120;i++)system.update(1/30,i/30);assert.ok(system.activeBoss.attackIndex>0);system.dispose();assert.equal(f.gates.length,0);for(const enemy of f.enemies)disposeEnemy(enemy);
});

test('boss danger zones allow escape, cover and jumping before damage resolves',()=>{
  const f=arena(),system=new BossSystem({...f,getRound:()=>5,hurtPlayer:amount=>f.damage.push(amount)});system.start('summit');
  system.createWarning('mortar',new THREE.Vector3(),2,.6,20);system.updateWarnings(.3);assert.equal(f.damage.length,0);f.player.pos.x=4;system.updateWarnings(.4);assert.equal(f.damage.length,0);
  f.player.pos.set(0,.9,0);system.createWarning('pulse',new THREE.Vector3(),3,.5,20);system.updateWarnings(.6);assert.equal(f.damage.length,0);
  f.player.pos.set(0,0,0);f.combat.hitWorld.lineOfSight=()=>false;system.createWarning('mortar',new THREE.Vector3(),3,.5,20);system.updateWarnings(.6);assert.equal(f.damage.length,0);
  f.combat.hitWorld.lineOfSight=()=>true;system.createWarning('mortar',new THREE.Vector3(),3,.5,20);system.updateWarnings(.6);assert.deepEqual(f.damage,[20]);system.dispose();for(const enemy of f.enemies)disposeEnemy(enemy);
});

test('both boss patterns stay bounded, distinguish their attacks and abort cleanly on player death',()=>{
  for(const archetype of ['conductor','furnace']){
    const f=arena();f.world.bossZones[0].archetype=archetype;const system=new BossSystem({...f,getRound:()=>20,getModifiers:()=>({chaos:5}),emit:(event,payload)=>f.events.push([event,payload])});system.start('summit');const boss=system.getBoss();boss.health=boss.maxHealth*.3;
    for(let i=0;i<3600;i++){f.player.pos.set(Math.sin(i*.017)*5,0,Math.cos(i*.017)*5);system.update(1/30,i/30);assert.ok(system.telegraphs.length<=14);assert.ok(f.enemies.length<=6);assert.ok(Number.isFinite(boss.g.position.x));}
    const attacks=new Set(f.events.filter(([event])=>event==='boss-attack').map(([,payload])=>payload.kind));for(const kind of bossStats(archetype).pattern)assert.ok(attacks.has(kind),`${archetype} ${kind}`);
    f.player.health=0;system.update(.05);assert.equal(system.getBoss(),null);assert.equal(system.telegraphs.length,0);assert.deepEqual(f.gates.at(-1),['summit-gate',false]);assert.equal(f.rewards.length,0);system.dispose();for(const enemy of f.enemies)disposeEnemy(enemy);
  }
});

test('boss controllers inhabit the authored elevated arenas without losing their ground height',()=>{
  const f=arena(),colliders=[],world=createHillWorld({scene:f.scene,colliders,seed:27}),navigation=new Navigation(colliders,{heightAt:world.heightAt});
  for(const zone of world.bossZones){
    f.player.pos.copy(zone.position);const system=new BossSystem({...f,world,navigation,getRound:()=>12});assert.equal(system.start(zone.id),true);const boss=system.activeBoss;
    assert.equal(boss.g.position.y,zone.position.y);assert.equal(world.doors.find(door=>door.id===zone.gateId).closed,true);
    for(let i=0;i<180;i++){f.player.pos.copy(zone.position).add(new THREE.Vector3(Math.sin(i*.03)*4,0,Math.cos(i*.03)*4));system.update(1/30,i/30);assert.equal(boss.g.position.y,zone.position.y);assert.equal(navigation.blocked(boss.g.position.x,boss.g.position.z,.6,boss.g.position.y),false);}
    system.dispose();assert.equal(world.doors.find(door=>door.id===zone.gateId).closed,false);
  }
  for(const enemy of f.enemies)disposeEnemy(enemy);world.dispose();
});
