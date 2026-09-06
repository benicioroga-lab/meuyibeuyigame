import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {DogSystem,DogTraining,DOG_TALENTS,dogTalentStats} from '../systems/dog.js';
import {Navigation} from '../systems/navigation.js';

function makeDog(options={}){
  const scene=new THREE.Scene(),hero=new THREE.Group(),player={pos:new THREE.Vector3(0,0,0),cameraYaw:0},effects={sound(){},nova(){},burst(){}};scene.add(hero);
  return new DogSystem({scene,hero,player,enemies:[],navigation:new Navigation([]),combat:{effects,game:{reward(){}},damage(){},chain(){},applyStatus(){}},...options});
}
test('support and survival talents have bounded costs and require currency and rounds',()=>{
  const training=new DogTraining(),wallet={coins:10000};assert.equal(training.buyTalent('rescue',wallet,1),false);assert.equal(wallet.coins,10000);assert.equal(training.buyTalent('unknown',wallet,99),false);
  for(const id of Object.keys(DOG_TALENTS)){const before=training.talentStats(),next=training.talentNext(id),comparison=training.talentComparison(id);assert.deepEqual(training.talentStats(),before);assert.ok(next.level>before.level);assert.ok(comparison.next>comparison.current);}
  assert.equal(training.buyTalent('scout',wallet,1),true);assert.equal(training.talentStats().ammoRange,8);assert.equal(training.buyTalent('scout',wallet,1),true);assert.equal(training.talentStats().ammoRange,12);assert.equal(training.buyTalent('scout',wallet,99),false);
  assert.equal(training.buyTalent('courier',{coins:NaN},1),false);assert.equal(dogTalentStats({scout:900}).ammoRange,12);
});
test('dog stats retain combat upgrades and cap permanent health bonuses',()=>{
  const training=new DogTraining({healthMultiplier:10});assert.equal(training.stats().health,84);const wallet={coins:5000};assert.equal(training.buy('bite',wallet,1),true);assert.equal(training.stats().damage,21);assert.equal(training.buyTalent('courier',wallet,1),true);assert.equal(training.stats().level,3);
});
test('build synergy scales Faro combat once without changing purchased training stats',()=>{
  const dog=makeDog();dog.combat.game.getModifiers=()=>({dogDamage:1.3,dogCooldown:.86});const base=dog.training.stats(),runtime=dog.runtimeStats();assert.equal(runtime.damage,base.damage*1.3);assert.equal(runtime.attackCooldown,base.attackCooldown*.86);assert.equal(dog.training.stats().damage,base.damage);dog.dispose();
});
test('Faro fetches eligible loot through the real collector and follow command stops fetching',()=>{
  const drop={type:'ammo',position:new THREE.Vector3(-1.8,0,-1)},seen=[];let collections=0;
  const dog=makeDog({loot:{nearest(position,types){seen.push(types);return drop;},collect(item,options){assert.equal(item,drop);assert.equal(options.collector,'dog');drop.collected=true;collections++;return true;}}});
  dog.training.talents.scout=1;dog.update(.016,1);assert.equal(collections,1);assert.deepEqual(seen[0],['ammo']);assert.equal(dog.satchels.visible,true);dog.command();drop.collected=false;dog.update(.5,2);assert.equal(collections,1);dog.dispose();
});
test('protection and distraction activate only in danger, honor cooldowns, and affect valid targets',()=>{
  const state={health:90,maxHealth:100},shields=[];const enemy={disabled:false,g:new THREE.Group(),config:{type:'ranged'},healthTimer:0};enemy.g.position.set(-1.8,0,1);
  const dog=makeDog({enemies:[enemy],getPlayerState:()=>state,grantShield:(...args)=>shields.push(args)});dog.training.talents.barrier=1;dog.training.talents.decoy=1;dog.training.talents.tracker=1;
  dog.updateSupport(.1);assert.equal(shields.length,0);assert.equal(enemy.tauntTarget,undefined);assert.ok(enemy.healthTimer>0);
  state.health=40;dog.updateSupport(.1);assert.equal(shields.length,1);assert.equal(shields[0][0],16);assert.equal(enemy.tauntTarget,dog);assert.equal(enemy.tauntTime,2.8);dog.updateSupport(.1);assert.equal(shields.length,1);dog.dispose();
});
test('rescue requires a talent, a living dog, physical proximity and time; succeeds once per run',()=>{
  const revivals=[],dog=makeDog({revivePlayer:fraction=>revivals.push(fraction)});assert.equal(dog.canRevive(),false);assert.equal(dog.onPlayerDowned(),false);dog.training.talents.rescue=1;dog.g.position.set(0,0,1);assert.equal(dog.onPlayerDowned(),true);
  assert.equal(dog.tryRevive(1),false);assert.equal(revivals.length,0);assert.equal(dog.tryRevive(2.1),true);assert.equal(revivals.length,1);assert.ok(Math.abs(revivals[0]-.3)<1e-9);assert.equal(dog.canRevive(),false);assert.equal(dog.onPlayerDowned(),false);dog.dispose();
});
test('rescue fails when Faro is downed and terrain height is retained when returning home',()=>{
  const navigation=new Navigation([]);navigation.heightAt=()=>6;const dog=makeDog({navigation,revivePlayer:()=>true});dog.player.pos.y=6;dog.training.talents.rescue=1;dog.onPlayerDowned();dog.downed=1;assert.equal(dog.tryRevive(.1),false);assert.equal(dog.rescuing,false);dog.update(1.1,1);assert.equal(dog.g.position.y,6);dog.dispose();
});
test('another revival cancels a pending Faro rescue without spending his charge',()=>{
  const state={downed:true},dog=makeDog({getPlayerState:()=>state,revivePlayer:()=>assert.fail('already revived')});dog.training.talents.rescue=1;dog.onPlayerDowned();state.downed=false;assert.equal(dog.tryRevive(4),false);assert.equal(dog.rescueUsed,false);assert.equal(dog.rescuing,false);dog.dispose();
});
