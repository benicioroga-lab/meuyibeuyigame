import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {CombatSystem} from '../systems/combat.js';
import {CombatEffects,WeaponView} from '../systems/combat-effects.js';
import {createEnemy} from '../systems/enemies.js';
import {stockWeapon} from '../systems/weapon-rolls.js';

function fixture(){
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(66,1,.05,200),dog=new THREE.Group(),enemies=[],kills=[],dealt=[];
  camera.position.set(0,1.14,0);camera.lookAt(0,1.14,8);scene.add(camera,dog);camera.updateMatrixWorld(true);
  const player={pos:new THREE.Vector3(),cameraYaw:0,aiming:true,thirdPerson:false,moveVelocity:new THREE.Vector3()},modifiers={};
  const game={scene,camera,dog,player,enemies,colliders:[],props:[],active:()=>true,settings:()=>({reduceMotion:true}),time:()=>0,getAudio:()=>null,getVolume:()=>0,getModifiers:()=>modifiers,toast(){},reward(){},onKill:(e,s,d)=>kills.push(d),onDamageDealt:(amount,detail)=>dealt.push({amount,detail})};
  const combat=new CombatSystem(game);combat.arsenal.random=()=>.99;
  const spawn=(type='grunt',x=0,z=8,hp=1000)=>{const enemy=createEnemy(scene,{x,z,type,seed:2});enemy.health=enemy.maxHealth=hp;enemies.push(enemy);return enemy;};
  return {scene,camera,dog,enemies,kills,dealt,player,game,combat,modifiers,spawn};
}

test('aimed gun damage registers in the same call, consumes one round, and cannot bypass cadence',()=>{
  const f=fixture(),enemy=f.spawn(),config=f.combat.arsenal.stats();
  assert.equal(f.combat.fire(),true);assert.equal(enemy.health,1000-config.damage);assert.equal(f.combat.arsenal.current.magazine,config.magazineSize-1);
  assert.equal(f.combat.fire(),false);assert.equal(enemy.health,1000-config.damage);assert.equal(f.dealt.length,1);f.combat.dispose();
});
test('headshots use rolled critical multiplier and send exactly one kill transaction',()=>{
  const f=fixture(),enemy=f.spawn('grunt',0,8,20);f.camera.position.y=1.8;f.camera.lookAt(0,1.8,8);
  const base=f.combat.arsenal.stats();f.combat.arsenal.current.roll.rolls.criticalMultiplier=1.5;
  assert.equal(f.combat.fire(),true);assert.equal(enemy.health,0);assert.equal(f.kills.length,1);assert.equal(f.kills[0].headshot,true);
  assert.equal(f.kills[0].damage,Math.round(base.damage*f.combat.arsenal.stats().criticalMultiplier));assert.equal(f.kills[0].actual,20);
  f.combat.damage(enemy,100);assert.equal(f.kills.length,1);f.combat.dispose();
});
test('actual shield surfaces absorb frontal fire, break once, and expose HP to the next shot',()=>{
  const f=fixture(),enemy=f.spawn('shield');enemy.g.rotation.y=Math.PI;enemy.shieldHealth=10;
  assert.equal(f.combat.preview().hits[0].zone,'shield');f.combat.fire();assert.equal(enemy.health,1000);assert.equal(enemy.shieldHealth,0);assert.equal(enemy.shieldBroken,true);assert.equal(enemy.shield.mesh.visible,false);
  f.combat.beginFrame(1);f.combat.fire();assert.ok(enemy.health<1000);assert.equal(f.dealt.length,1);f.combat.dispose();
});
test('shield flanks and exposed legs use actual mesh zones without an invisible frontal resistance',()=>{
  const f=fixture(),enemy=f.spawn('shield');const shield=enemy.shieldHealth;
  f.combat.damage(enemy,40,{zone:'torso'});assert.equal(enemy.health,960);assert.equal(enemy.shieldHealth,shield);
  f.combat.damage(enemy,5,{zone:'leg',direction:new THREE.Vector3(1,0,0)});assert.equal(enemy.hitRegion,'leg');assert.ok(enemy.stunTime>0);assert.equal(enemy.lastHit.direction.x,1);f.combat.dispose();
});
test('a shotgun divides total trigger damage between pellets and keeps finite ammunition',()=>{
  const f=fixture(),enemy=f.spawn();f.combat.arsenal.grant('cascade');f.combat.arsenal.equip('cascade');f.combat.beginFrame(1);
  // Remove spread for this measurement: all actual mesh ray hits must sum to the total damage.
  const original=f.combat.arsenal.fire.bind(f.combat.arsenal);f.combat.arsenal.fire=options=>{const shot=original(options);return shot?{...shot,spread:0}:shot;};
  const stats=f.combat.arsenal.stats();f.combat.fire();assert.equal(1000-enemy.health,stats.damage);assert.equal(f.combat.arsenal.current.magazine,stats.magazineSize-1);assert.equal(f.dealt.length,stats.pellets);f.combat.dispose();
});
test('burst attachment completes on simulation ticks, spends real ammo, and pauses with the simulation',()=>{
  const f=fixture();f.spawn();const roll=stockWeapon('boardwalk');roll.uid='burst-test';roll.rarity='rare';roll.attachments.receiver={id:'burst',manufacturer:'remendo'};
  const id=f.combat.arsenal.addLoot(roll);f.combat.arsenal.equip(id);f.combat.beginFrame(1);const initial=f.combat.arsenal.current.magazine;
  f.combat.fire();assert.equal(f.combat.effects.counter.shots,1);f.combat.beginFrame(.08);assert.equal(f.combat.effects.counter.shots,2);f.combat.beginFrame(.08);assert.equal(f.combat.effects.counter.shots,3);assert.equal(f.combat.arsenal.current.magazine,initial-3);
  const before=f.combat.arsenal.cooldown;assert.equal(f.combat.fire(),false);assert.equal(f.combat.arsenal.cooldown,before);f.combat.dispose();
});
test('temporary ammunition and damage modifiers apply once and normal ammo use resumes afterward',()=>{
  const f=fixture(),enemy=f.spawn();f.modifiers.damage=2;f.modifiers.infiniteAmmo=true;f.combat.arsenal.current.magazine=0;
  const expected=f.combat.arsenal.stats().damage;assert.equal(f.combat.fire(),true);assert.equal(1000-enemy.health,expected);assert.equal(f.combat.arsenal.current.magazine,0);
  delete f.modifiers.infiniteAmmo;f.combat.beginFrame(1);assert.equal(f.combat.fire(),false);assert.equal(f.combat.arsenal.reloadState.kind,'empty');f.combat.dispose();
});
test('burn ticks have a bounded duration, and corrosive damage weakens actual resistance',()=>{
  const f=fixture(),enemy=f.spawn();f.combat.applyStatus(enemy,{effect:'fire',burnDamage:9,burnDuration:3});
  for(let i=0;i<60;i++)f.combat.beginFrame(.05);assert.equal(enemy.health,973);for(let i=0;i<40;i++)f.combat.beginFrame(.05);assert.equal(enemy.health,973);
  enemy.config={...enemy.config,resist:{kinetic:.5}};assert.equal(f.combat.damage(enemy,20),10);f.combat.applyStatus(enemy,{effect:'corrosive'});assert.equal(f.combat.damage(enemy,20),15);f.combat.dispose();
});
test('cryo buildup freezes after four impacts and a boss receives a shorter control window',()=>{
  const f=fixture(),enemy=f.spawn(),boss=f.spawn('tank',2);boss.boss=true;
  for(let i=0;i<4;i++){f.combat.applyStatus(enemy,{effect:'cryo'});f.combat.applyStatus(boss,{effect:'cryo'});}
  assert.equal(enemy.freezeTime,1.15);assert.equal(boss.freezeTime,.3);assert.equal(enemy.frostStacks,0);f.combat.dispose();
});
test('electric chains never revisit a target and area damage cannot cross cover',()=>{
  const f=fixture(),first=f.spawn('grunt',0,8),second=f.spawn('grunt',2,8),third=f.spawn('grunt',4,8);f.combat.chain(first,10,8,5);
  assert.equal(first.health,1000);assert.equal(second.health,990);assert.equal(third.health,990);
  f.game.colliders.push({x:0,z:6,width:20,depth:.1,height:4});f.combat.area(new THREE.Vector3(0,1,4),8,100);assert.equal(first.health,1000);assert.equal(second.health,990);f.combat.dispose();
});
test('the headshot build explosion deals the advertised fraction and self-destruction never grants weapon procs',()=>{
  const f=fixture(),first=f.spawn('grunt',0,8,10),second=f.spawn('grunt',1.5,8);f.modifiers.headshotExplosion=.25;
  f.combat.damage(first,100,{source:'weapon',headshot:true,weaponId:f.combat.arsenal.currentId});assert.equal(second.health,975);
  const other=f.spawn('grunt',5,8,10);f.combat.arsenal.current.roll.perk='tempo';const streak=f.combat.killStreak;
  f.combat.damage(other,100,{source:'self',weaponId:f.combat.arsenal.currentId});assert.equal(f.combat.arsenal.current.tempoStacks,0);assert.equal(f.combat.killStreak,streak);assert.equal(f.kills.length,2);f.combat.dispose();
});
test('effects remain bounded during a long automatic-fire simulation and release every render object',()=>{
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(),fx=new CombatEffects({scene,camera,reduceMotion:()=>false});
  for(let tick=0;tick<3600;tick++){fx.burst(new THREE.Vector3(),'#ffcc99',6,1);fx.shell(new THREE.Vector3(),camera,{effect:'kinetic'});fx.beam(new THREE.Vector3(),new THREE.Vector3(0,0,10),'#ffcc99');fx.update(1/60);assert.ok(fx.items.length<=140);}
  fx.dispose();assert.equal(scene.children.length,0);assert.equal(fx.items.length,0);assert.equal(fx.materials.size,0);
});
test('weapon models animate inspection and empty reload while staying hidden in third person',()=>{
  const view=new WeaponView(new THREE.PerspectiveCamera(),new THREE.Group()),config={id:'test',family:'shotgun',color:'#ffeeaa',effect:'kinetic',recoil:.03};view.equip(config);view.update(.4,{active:true});
  view.inspect();view.update(.5,{active:true});assert.ok(Math.abs(view.root.rotation.y)>.1);view.recoil(config);assert.equal(view.inspection,0);
  view.update(.05,{active:true,reload:{kind:'empty',remaining:.6,total:1}});assert.equal(view.magazine.visible,false);
  view.update(.05,{active:true,aiming:true,thirdPerson:true});assert.equal(view.root.visible,false);assert.equal(view.worldRoot.visible,false);
  const geometry=view.ownedGeometries[0];let disposed=false;geometry.addEventListener('dispose',()=>disposed=true);view.equip({...config,id:'other'});assert.equal(disposed,false);view.update(.1,{active:true});assert.equal(disposed,true);view.dispose();
});
