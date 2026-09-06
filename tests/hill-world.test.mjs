import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {createHillWorld,createSurfaceSampler} from '../systems/hill-world.js';
import {Navigation} from '../systems/navigation.js';

function fixture(seed=17){const scene=new THREE.Scene(),colliders=[],world=createHillWorld({scene,colliders,seed}),nav=new Navigation(colliders,{heightAt:world.heightAt});return {scene,colliders,world,nav};}
function reaches(nav,from,to,radius=.4){const path=nav.path(from,to,radius);assert.ok(path.length,`No path to ${to.toArray()}`);assert.ok(path.at(-1).distanceTo(to)<.3,`Path stopped at ${path.at(-1).toArray()} before ${to.toArray()}`);return path;}

test('surface selection preserves stacked interior, roof, tunnel and walkable steps',()=>{
  const height=createSurfaceSampler([{x:0,z:0,width:10,depth:10,height:0},{x:0,z:0,width:10,depth:10,height:4}]);
  assert.equal(height(0,0,0),0);assert.equal(height(0,0,4),4);assert.equal(height(0,0,3.6),4);assert.equal(height(0,0,Infinity),4);assert.equal(height(9,9,4),0);
  const {world}=fixture();assert.equal(world.heightAt(0,9,0),0);assert.equal(world.heightAt(0,9,6),6);
  assert.equal(world.heightAt(-20,-30,0),0);assert.equal(world.heightAt(-20,-30,3.8),3.8);
  assert.equal(world.heightAt(27,48,9),9);assert.equal(world.heightAt(0,82,12),12);world.dispose();
});

test('all three terraces remain connected while paid shortcut stays closed',()=>{
  const {world,nav}=fixture();assert.equal(world.doors.find(d=>d.id==='varal-shortcut').closed,true);
  const target=new THREE.Vector3(0,12,82),path=reaches(nav,world.spawn,target);
  assert.ok(path.some(p=>p.y>2&&p.y<5),'path must use an actual slope');assert.ok(path.some(p=>p.y===6),'middle terrace');assert.ok(path.some(p=>p.y===12),'summit');
  reaches(nav,target,world.spawn);world.dispose();
});

test('enemy physically ascends and descends with collision-safe footsteps',()=>{
  const {world,nav}=fixture(),entity={g:new THREE.Group(),seed:1};entity.g.position.set(20,0,-16);
  const top=new THREE.Vector3(20,6,4.3),bottom=new THREE.Vector3(20,0,-16.5);let maximum=0;
  for(const goal of [top,bottom])for(let frame=0;frame<500;frame++){
    const previous=entity.g.position.clone();nav.move(entity,goal,4,1/30,.4);maximum=Math.max(maximum,entity.g.position.y);
    assert.equal(nav.blocked(entity.g.position.x,entity.g.position.z,.39,entity.g.position.y),false);
    assert.ok(Math.abs(entity.g.position.y-previous.y)<=.56,'no teleporting between floors');
  }
  assert.ok(maximum>=6);assert.ok(entity.g.position.distanceTo(bottom)<.3);world.dispose();
});

test('stairs and rooftop cache are reachable without jumping or crossing a wall',()=>{
  const {world,nav}=fixture();world.openDoor('varal-shortcut');
  const stairStart=new THREE.Vector3(-11,0,-18),stairEnd=new THREE.Vector3(-11,6,5);reaches(nav,stairStart,stairEnd);
  const cache=world.interactions.find(i=>i.id==='roof-cache');reaches(nav,world.spawn,cache.position);
  const entity={g:new THREE.Group(),seed:2};entity.g.position.copy(stairStart);
  for(let n=0;n<480;n++)nav.move(entity,stairEnd,3,1/30,.4);
  assert.ok(entity.g.position.distanceTo(stairEnd)<.3);world.dispose();
});

test('vault door blocks the subterranean route and opening it does not teleport to its roof',()=>{
  const {world,nav}=fixture(),start=new THREE.Vector3(0,0,9),target=new THREE.Vector3(0,0,19);
  assert.equal(nav.clearLine(start,target,.4),false);world.openDoor('gallery-vault');
  assert.equal(nav.clearLine(start,target,.4),true);const path=reaches(nav,start,target);assert.ok(path.every(p=>p.y===0));
  reaches(nav,target,new THREE.Vector3(11,6,37));world.dispose();
});

test('boss gates close their only entry, reopen immediately, and invalidate navigation cache',()=>{
  const {world,nav}=fixture();for(const zone of world.bossZones){const inside=zone.entry.clone();inside.z+=4;
    assert.equal(nav.clearLine(zone.entry,inside,.4),true);world.setGate(zone.gateId,true);assert.equal(nav.clearLine(zone.entry,inside,.4),false);
    world.setGate(zone.gateId,false);assert.equal(nav.clearLine(zone.entry,inside,.4),true);
  }world.dispose();
});

test('seeded secrets and every authored interaction are on accessible ground',()=>{
  for(const seed of [1,17,90]){
    const {world,nav}=fixture(seed);world.openDoor('gallery-vault');world.openDoor('varal-shortcut');
    for(const item of world.interactions){assert.equal(nav.blocked(item.position.x,item.position.z,.35,item.position.y),false,item.id);reaches(nav,world.spawn,item.position,.35);}
    for(const p of world.spawnPoints)assert.equal(nav.blocked(p.x,p.z,.4,p.y),false,`spawn ${p.toArray()}`);
    world.dispose();
  }
});

test('world disposal removes its render objects and colliders while preserving external objects',()=>{
  const scene=new THREE.Scene(),external={x:100,z:100,width:1,depth:1,height:2},colliders=[external],world=createHillWorld({scene,colliders,seed:8});
  assert.ok(colliders.length>100);world.dispose();assert.deepEqual(colliders,[external]);assert.equal(world.group.parent,null);
});
