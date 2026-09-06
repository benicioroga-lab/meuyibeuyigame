import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {movePlayer} from '../systems/player-movement.js';
import {createHillWorld,createSurfaceSampler} from '../systems/hill-world.js';
import {Navigation} from '../systems/navigation.js';

function player(position=new THREE.Vector3()) {return {pos:position.clone(),velocity:new THREE.Vector3(),moveVelocity:new THREE.Vector3(),cameraYaw:0,dir:0,onGround:true,dash:0};}
function fixture() {const colliders=[],world=createHillWorld({scene:new THREE.Scene(),colliders,seed:17}),navigation=new Navigation(colliders,{heightAt:world.heightAt});return {world,navigation};}
function frames(p,count,keys,context,dt=1/60) {for(let i=0;i<count;i++)movePlayer(p,dt,{keys,...context});}
function flat(colliders=[]) {const world={heightAt:()=>0,bounds:{minX:-50,maxX:50,minZ:-50,maxZ:50},spawn:new THREE.Vector3()};return {world,navigation:new Navigation(colliders,{heightAt:world.heightAt})};}

test('player climbs and descends the authored ramp without jumping or vertical snaps',()=>{
  const f=fixture(),p=player(new THREE.Vector3(20,0,-16.8));let max=0;
  for(let i=0;i<240;i++){const oldY=p.pos.y;movePlayer(p,1/60,{...f,keys:{KeyW:true}});assert.ok(Math.abs(p.pos.y-oldY)<.11);assert.equal(p.onGround,true);max=Math.max(max,p.pos.y);}
  assert.ok(max>=6);assert.ok(p.pos.z>4);frames(p,240,{KeyS:true},f);assert.ok(p.pos.y<.1);assert.ok(p.pos.z<-16);f.world.dispose();
});

test('player steps up and down stairs while radius collision clears the next riser',()=>{
  const f=fixture();f.world.openDoor('varal-shortcut');const p=player(new THREE.Vector3(-11,0,-17.5));let max=0;
  for(let i=0;i<260;i++){const before=p.pos.y;movePlayer(p,1/60,{...f,keys:{KeyW:true}});assert.ok(Math.abs(p.pos.y-before)<=.31);max=Math.max(max,p.pos.y);assert.equal(p.onGround,true);}
  assert.equal(max,6);assert.ok(p.pos.z>4);frames(p,260,{KeyS:true},f);assert.ok(p.pos.y<.01);f.world.dispose();
});

test('jump lands on the original floor with finite vertical velocity',()=>{
  const p=player(),f=flat();p.onGround=false;p.velocity.y=9.2;let peak=0;
  for(let i=0;i<100;i++){movePlayer(p,1/60,{...f,keys:{}});peak=Math.max(peak,p.pos.y);}
  assert.ok(peak>1.8&&peak<2.2);assert.equal(p.pos.y,0);assert.equal(p.onGround,true);assert.equal(p.velocity.y,0);
});

test('jumping inside the tunnel hits its ceiling and never lands on the street above',()=>{
  const f=fixture(),p=player(new THREE.Vector3(0,0,9));p.onGround=false;p.velocity.y=15;let peak=0;
  for(let i=0;i<110;i++){movePlayer(p,1/60,{...f,keys:{}});peak=Math.max(peak,p.pos.y);assert.ok(p.pos.y+1.4<=3.42,'head crossed ceiling');}
  assert.ok(peak>1.3&&peak<=2.02);assert.equal(p.pos.y,0);assert.equal(p.onGround,true);f.world.dispose();
});

test('jump cannot tunnel through a thin elevated ceiling during a delayed frame',()=>{
  const surfaces=[{x:0,z:0,width:20,depth:20,height:0},{x:0,z:0,width:20,depth:20,height:3}],colliders=[{x:0,z:0,width:20,depth:20,minY:2.8,height:3,surface:true}],heightAt=createSurfaceSampler(surfaces);
  const f={world:{heightAt,bounds:{minX:-10,maxX:10,minZ:-10,maxZ:10},spawn:new THREE.Vector3()},navigation:new Navigation(colliders,{heightAt})},p=player();p.onGround=false;p.velocity.y=30;
  movePlayer(p,.2,{...f,keys:{}});assert.ok(p.pos.y+1.4<=2.82,'jump crossed the ceiling');frames(p,150,{},f);assert.equal(p.pos.y,0);
});

test('a fast dash is swept against thin walls and does not cross closed gates',()=>{
  const f=flat([{x:0,z:2,width:10,depth:.06,minY:0,height:4}]),p=player();p.dash=1;
  frames(p,30,{KeyW:true},f);assert.ok(p.pos.z<1.6);assert.equal(f.navigation.blocked(p.pos.x,p.pos.z,.37,p.pos.y),false);
  const hill=fixture(),q=player(new THREE.Vector3(-11,0,-19));q.dash=1;frames(q,30,{KeyW:true},hill);assert.ok(q.pos.z<-16.6);hill.world.dispose();
});

test('normalized diagonal movement, ADS, downed state and dash obey their speed multipliers',()=>{
  const f=flat(),a=player(),b=player();frames(a,60,{KeyW:true},f);frames(b,60,{KeyW:true,KeyD:true},f);assert.ok(Math.abs(a.pos.length()-b.pos.length())<.0001);
  const ads=player();ads.aiming=true;frames(ads,60,{KeyW:true},f);assert.ok(Math.abs(ads.pos.z/a.pos.z-.7)<.001);
  const down=player();down.downed=true;frames(down,60,{KeyW:true},f);assert.ok(Math.abs(down.pos.z/a.pos.z-.22)<.001);
  const dash=player();dash.dash=2;frames(dash,60,{KeyW:true},f);assert.ok(Math.abs(dash.pos.z/a.pos.z-2.2)<.001);
});

test('walking from an accessible rooftop falls to ground instead of floating or snapping',()=>{
  const f=fixture(),p=player(new THREE.Vector3(-20,3.8,-26));frames(p,90,{KeyW:true},f);assert.equal(p.pos.y,0);assert.equal(p.onGround,true);f.world.dispose();
});

test('world bounds stop extreme-speed movement and downward falls recover valid ground',()=>{
  const f=flat(),p=player();p.dash=1;movePlayer(p,1,{...f,keys:{KeyW:true},modifiers:{moveSpeed:100}});assert.ok(p.pos.z<=49.3);assert.ok(Number.isFinite(p.pos.y));
  p.onGround=false;p.pos.y=20;p.velocity.y=-50;movePlayer(p,.5,{...f,keys:{}});assert.equal(p.pos.y,0);assert.equal(p.onGround,true);
});
