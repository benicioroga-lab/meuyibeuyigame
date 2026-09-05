import {test,after} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {CombatSystem} from '../systems/combat.js';
import {DogSystem} from '../systems/dog.js';
import {Navigation} from '../systems/navigation.js';
import {createEnemy,updateEnemyAI,disposeEnemy} from '../systems/enemies.js';
import {WEAPONS,wavePlan} from '../systems/config.js';

// A DOM adapter only for feedback; physics, rigs, raycasting, guns and AI are the actual modules.
const elements=new Map();
function element(){return {textContent:'',dataset:{},style:{setProperty(){}},classList:{add(){},remove(){},toggle(){}},append(){},remove(){}};}
const oldDocument=globalThis.document;
globalThis.document={getElementById:id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id);},querySelector:()=>element(),createElement:()=>element()};
globalThis.innerWidth=1280;globalThis.innerHeight=720;
after(()=>{globalThis.document=oldDocument;delete globalThis.innerWidth;delete globalThis.innerHeight;});
function fixture(){
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(66,16/9,.05,150),dog=new THREE.Group(),enemies=[],colliders=[],props=[],rewards=[];
  scene.add(camera,dog);const player={pos:new THREE.Vector3(),moveVelocity:new THREE.Vector3(),cameraYaw:0,aiming:true,firing:0,health:100};
  let time=0,active=true,kills=0;
  const combat=new CombatSystem({scene,camera,dog,player,enemies,colliders,props,getBoss:()=>null,settings:()=>({reduceMotion:false}),active:()=>active,time:()=>time,getAudio:()=>null,getVolume:()=>0,toast(){},reward:value=>rewards.push(value),damageBoss(){},hitProp(){},onKill:()=>kills++});
  combat.arsenal.random=()=>1;
  const navigation=new Navigation(colliders),companion=new DogSystem({scene,hero:dog,player,enemies,navigation,combat,toast(){}});
  const spawn=(x=0,z=8,type='grunt',round=1)=>{const e=createEnemy(scene,{x,z,type,round,roundEnemy:true,seed:enemies.length+1});enemies.push(e);return e;};
  const aim=enemy=>{camera.position.copy(player.pos).add(new THREE.Vector3(0,1.3,0));const at=enemy.g.position.clone().add(new THREE.Vector3(0,enemy.config.scale*1.2,0));camera.lookAt(at);camera.updateMatrixWorld(true);player.cameraYaw=Math.atan2(at.x-player.pos.x,at.z-player.pos.z);};
  const step=dt=>{time+=dt;combat.beginFrame(dt);for(const enemy of enemies)updateEnemyAI(enemy,{dt,player,companion,navigation,peers:enemies,hurtPlayer(){},hurtDog:n=>companion.hurt(n),fireRanged(){},camera,time});companion.update(dt,time);combat.update(dt);};
  return {scene,camera,dog,player,combat,companion,enemies,colliders,navigation,spawn,aim,step,rewards,kills:()=>kills,setActive:value=>active=value};
}
test('trigger applies damage in the same call, confirms hits, and pays exactly once per kill',()=>{
  const f=fixture(),enemy=f.spawn();f.aim(enemy);
  assert.equal(f.combat.fire(),true);assert.equal(enemy.health,20);assert.equal(f.combat.effects.counter.hits,1);
  assert.equal(f.combat.fire(),false);assert.equal(enemy.health,20);
  f.combat.beginFrame(.4);f.combat.fire();assert.equal(enemy.health,0);assert.equal(f.kills(),1);
  f.combat.damage(enemy,100);assert.equal(f.kills(),1);assert.equal(f.combat.effects.counter.kills,1);
  f.combat.dispose();f.companion.dispose();
});
test('chain damage selects unique enemies and respects cover',()=>{
  const f=fixture(),first=f.spawn(0,8),second=f.spawn(2,8),covered=f.spawn(4,8);
  f.colliders.push({x:3,z:8,width:.3,depth:5,height:4});
  f.combat.chain(first,10,5,5);
  assert.equal(first.health,42);assert.equal(second.health,32);assert.equal(covered.health,42);
  f.combat.dispose();f.companion.dispose();
});
test('burn damage stops after expiration and frost expires without changing the base speed',()=>{
  const f=fixture(),enemy=f.spawn(0,40,'tank');
  f.combat.applyStatus(enemy,{effect:'burn',burnDuration:3,burnDamage:9});
  for(let i=0;i<80;i++)f.combat.beginFrame(.05);
  const hp=enemy.health;f.combat.beginFrame(10);assert.equal(enemy.health,hp);assert.ok(hp<enemy.maxHealth);
  const speed=enemy.config.speed;f.combat.applyStatus(enemy,{effect:'frost',slow:.5,slowDuration:1});
  for(let i=0;i<30;i++)f.step(.05);
  assert.equal(enemy.slowTime,0);assert.equal(enemy.config.speed,speed);
  f.combat.dispose();f.companion.dispose();
});
test('Faro recovers from incapacitation and purchased upgrades change the visual tier',()=>{
  const f=fixture(),wallet={coins:10000};f.companion.hurt(1000);assert.equal(f.companion.health,0);
  for(let i=0;i<190;i++)f.step(.05);
  assert.ok(f.companion.health>0);assert.ok(f.companion.downed<=0);assert.equal(f.companion.g.rotation.z,0);
  f.companion.upgrade('bite',wallet,1);f.companion.upgrade('agility',wallet,1);assert.equal(f.companion.collar.visible,true);
  for(const round of [3,7,11])f.companion.upgrade('element',wallet,round);
  assert.equal(f.companion.visualTier,3);assert.equal(f.companion.aura.visible,true);assert.equal(f.companion.heroTrim.visible,true);
  f.combat.dispose();f.companion.dispose();
});
test('five simulated minutes across all seven weapons keep ammo, actors and effects in valid bounded states',()=>{
  const f=fixture();let wave=1,spawned=0,weaponIndex=0,maxEffects=0,maxNumbers=0,shots=0;
  const startWave=()=>{for(const type of wavePlan(wave).types){const angle=spawned++*2.399;f.spawn(Math.sin(angle)*16,Math.cos(angle)*16,type,wave);}wave++;};
  startWave();
  for(let frame=0;frame<9000;frame++){
    const nextWeapon=Math.min(6,Math.floor(frame/1200));
    if(nextWeapon!==weaponIndex){weaponIndex=nextWeapon;f.combat.arsenal.grant(WEAPONS[weaponIndex].id);f.combat.arsenal.equip(WEAPONS[weaponIndex].id);}
    const angle=frame/30*.16;f.player.pos.set(Math.sin(angle)*5,0,Math.cos(angle)*5);
    const target=f.enemies.filter(e=>!e.disabled).sort((a,b)=>a.g.position.distanceToSquared(f.player.pos)-b.g.position.distanceToSquared(f.player.pos))[0];
    if(target){f.aim(target);if(f.combat.fire())shots++;}
    if(frame%600===0)f.combat.arsenal.addAmmo(2);
    f.step(1/30);
    for(let i=f.enemies.length-1;i>=0;i--)if(f.enemies[i].disabled&&f.enemies[i].deathTime>1.8){disposeEnemy(f.enemies[i]);f.enemies.splice(i,1);}
    if(!f.enemies.some(e=>!e.disabled))startWave();
    for(const e of f.enemies){assert.ok(Number.isFinite(e.g.position.x)&&Number.isFinite(e.g.position.z));assert.ok(e.health>=0&&e.health<=e.maxHealth);}
    const entry=f.combat.arsenal.current,config=f.combat.arsenal.stats();assert.ok(entry.magazine>=0&&entry.magazine<=config.magazineSize);assert.ok(entry.reserve>=0&&entry.reserve<=config.maxReserve);
    maxEffects=Math.max(maxEffects,f.combat.effects.items.length);maxNumbers=Math.max(maxNumbers,f.combat.effects.numbers.length);
  }
  assert.ok(shots>400,`shots: ${shots}`);assert.ok(f.kills()>100,`kills: ${f.kills()}`);assert.equal(weaponIndex,6);
  assert.ok(maxEffects<=140);assert.ok(maxNumbers<=22);assert.ok(f.enemies.length<=40);
  for(let i=0;i<100;i++)f.combat.effects.update(.05);
  assert.equal(f.combat.effects.items.length,0);assert.equal(f.combat.effects.numbers.length,0);
  f.combat.dispose();f.companion.dispose();
});
