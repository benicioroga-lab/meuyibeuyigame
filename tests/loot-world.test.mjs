import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {Arsenal} from '../systems/arsenal.js';
import {LootWorld} from '../systems/loot-world.js';
import {HitWorld} from '../systems/hit-detection.js';
import {rollWeapon} from '../systems/weapon-rolls.js';

function fixture({colliders=[],world=null,maxDrops=60,director=null}={}){
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(),player={pos:new THREE.Vector3()},state={coins:0},sounds=[],messages=[];
  camera.position.set(0,1.2,0);camera.lookAt(0,.5,3);camera.updateMatrixWorld(true);
  const combat={arsenal:new Arsenal(),game:{camera},effects:{sound:(...args)=>sounds.push(args)},hitWorld:new HitWorld({colliders,props:[],enemies:[]}),updateHUD(){}};
  const dog={g:new THREE.Group()};dog.g.position.set(0,0,1);
  const loot=new LootWorld({scene,player,combat,state,world,maxDrops,director,getDog:()=>dog,toast:text=>messages.push(text),document:null,random:()=>.4});
  return {scene,camera,player,state,sounds,messages,combat,loot,dog};
}
test('money consolidates nearby drops and pays exactly once at actual collection',()=>{
  const {loot,state}=fixture();const first=loot.spawnMoney(24,new THREE.Vector3(.7,0,0));
  assert.equal(loot.spawnMoney(30,new THREE.Vector3(1,0,0)),first);assert.equal(first.amount,54);assert.equal(state.coins,0);
  loot.update(.1);assert.equal(state.coins,54);assert.equal(loot.drops.length,0);assert.equal(loot.collect(first),false);assert.equal(state.coins,54);loot.dispose();
});
test('money callback owns mutation, so animated rewards cannot double-pay',()=>{
  const {loot,state}=fixture();let calls=0;loot.reward=amount=>{state.coins+=amount;calls++;};
  loot.spawnMoney(100,new THREE.Vector3());loot.update(.1);assert.equal(calls,1);assert.equal(state.coins,100);loot.dispose();
});
test('solid cover and different floors block looting for players and the dog',()=>{
  const {loot,state,dog}=fixture({colliders:[{x:0,z:1,width:4,depth:.25,minY:0,height:3}]});
  const money=loot.spawnMoney(50,new THREE.Vector3(0,0,2));assert.equal(loot.collect(money),false);assert.equal(loot.nearest(new THREE.Vector3(),['money']),null);
  dog.g.position.set(0,0,2.5);assert.equal(loot.collect(money,{collector:'dog'}),true);assert.equal(state.coins,50);
  const roof=loot.spawnMoney(60,new THREE.Vector3(0,4,0));assert.equal(loot.collect(roof),false);loot.dispose();
});
test('world height uses the supplied floor reference instead of teleporting tunnel loot onto roofs',()=>{
  const references=[],world={heightAt(x,z,reference){references.push(reference);return reference>3?6:-2;}};
  const {loot}=fixture({world});const tunnel=loot.spawnAmmo(new THREE.Vector3(1,-2,1)),roof=loot.spawnAmmo(new THREE.Vector3(1,6,1));
  assert.deepEqual(references,[-2,6]);assert.equal(tunnel.position.y,-2);assert.equal(roof.position.y,6);loot.dispose();
});
test('ammo remains on the floor when full and conserves maximum reserve on pickup',()=>{
  const {loot,combat}=fixture();combat.arsenal.current.reserve=combat.arsenal.stats().maxReserve;
  const drop=loot.spawnAmmo(new THREE.Vector3(),2);assert.equal(loot.collect(drop),false);assert.ok(loot.drops.includes(drop));
  assert.equal(loot.nearest(new THREE.Vector3(),['ammo']),null,'Faro does not pursue ammo nobody can carry');
  combat.arsenal.current.reserve-=3;assert.equal(loot.collect(drop),true);assert.equal(combat.arsenal.current.reserve,combat.arsenal.stats().maxReserve);loot.dispose();
});
test('full weapon inventory preserves floor loot; recycling makes room for the exact roll',()=>{
  const {loot,combat}=fixture();for(let i=0;i<15;i++)assert.ok(combat.arsenal.addLoot(rollWeapon({seed:i+3,rarity:'rare'})));
  const roll=rollWeapon({seed:321,rarity:'legendary'}),drop=loot.spawnWeapon(roll,new THREE.Vector3(0,0,1));
  assert.equal(loot.collect(drop),false);assert.equal(loot.drops.length,1);
  const disposable=[...combat.arsenal.inventory.keys()][1];assert.ok(combat.arsenal.salvage(disposable,{coins:0}));
  assert.equal(loot.collect(drop,{equip:true}),true);assert.equal(combat.arsenal.current.roll.seed,321);assert.equal(combat.arsenal.current.roll.rarity,'legendary');assert.equal(loot.drops.length,0);loot.dispose();
});
test('a visible pickup prompt is always within collection range and full inventory consumes only that interaction',()=>{
  const {loot,combat,messages}=fixture();const drop=loot.spawnWeapon(rollWeapon({seed:701}),new THREE.Vector3(0,0,3.3));assert.equal(loot.focusDrop(),null);
  drop.position.z=2.8;drop.g.position.copy(drop.position);assert.equal(loot.focusDrop(),drop);
  for(let i=0;i<15;i++)combat.arsenal.addLoot(rollWeapon({seed:i+800}));assert.equal(loot.interact(),true,'Prevent falling through to opening a nearby paid chest');assert.ok(loot.drops.includes(drop));assert.match(messages.at(-1),/Mochila cheia/);loot.dispose();
});
test('attachment drops go into the bag; installation changes real weapon statistics',()=>{
  const {loot,combat}=fixture(),before=combat.arsenal.stats().magazineSize;
  const drop=loot.spawnAttachment('extended',new THREE.Vector3(), 'muralha');assert.equal(loot.collect(drop),true);
  assert.equal(combat.arsenal.attachmentStash.size,1);assert.equal(combat.arsenal.stats().magazineSize,before);
  assert.equal(combat.arsenal.equipAttachment([...combat.arsenal.attachmentStash.keys()][0]),true);assert.ok(combat.arsenal.stats().magazineSize>before);loot.dispose();
});
test('power-up activates its director effect once, rejects unknown ids and waits on failed activation',()=>{
  let calls=0,allowed=false;const director={activatePowerup(id){calls++;assert.equal(id,'nuke');return allowed;}};
  const {loot}=fixture({director});assert.equal(loot.spawnPowerup('invalid',new THREE.Vector3()),null);
  const drop=loot.spawnPowerup('nuke',new THREE.Vector3());assert.equal(loot.collect(drop),false);allowed=true;
  assert.equal(loot.collect(drop),true);assert.equal(loot.collect(drop),false);assert.equal(calls,2);loot.dispose();
});
test('bounded drops favor rare items and all shared GPU resources are disposed once',()=>{
  const {loot,scene}=fixture({maxDrops:4});for(let i=0;i<4;i++)loot.spawnMoney(20,new THREE.Vector3(i*4+10,0,0));
  const legendary=loot.spawnWeapon(rollWeapon({seed:44,rarity:'legendary'}),new THREE.Vector3(0,0,4));assert.ok(legendary);assert.equal(loot.drops.length,4);
  for(let i=0;i<30;i++)loot.spawnMoney(1,new THREE.Vector3(50+i*4,0,0));assert.equal(loot.drops.length,4);assert.ok(loot.drops.includes(legendary));
  let disposed=0;for(const geometry of Object.values(loot.geometry))geometry.addEventListener('dispose',()=>disposed++);
  loot.dispose();assert.equal(disposed,5);assert.equal(loot.drops.length,0);assert.equal(loot.group.parent,null);assert.equal(scene.children.length,0);
});
test('expiry removes stale dog targets and does not award distant uncollected money',()=>{
  const {loot,state}=fixture();const drop=loot.spawnMoney(40,new THREE.Vector3(30,0,0));loot.update(106);assert.equal(drop.active,false);assert.equal(loot.nearest(new THREE.Vector3(30,0,0),['money']),null);assert.equal(state.coins,0);loot.dispose();
});
test('magnet pulls visible loot without equipping ground weapons or crossing cover',()=>{
  const {loot,combat}=fixture({director:{modifiers:{magnet:true}}}),initial=combat.arsenal.currentId;
  const drop=loot.spawnWeapon(rollWeapon({seed:33,rarity:'rare'}),new THREE.Vector3(0,0,7));
  for(let i=0;i<60;i++)loot.update(1/60);assert.ok(drop.position.z<2);assert.equal(combat.arsenal.currentId,initial);assert.equal(loot.drops.length,1);loot.dispose();
});
