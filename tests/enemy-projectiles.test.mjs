import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {EnemyProjectiles,segmentPlayerHit} from '../systems/enemy-projectiles.js';
import {HitWorld} from '../systems/hit-detection.js';

function fixture(){
  const scene=new THREE.Scene(),player={pos:new THREE.Vector3(0,0,0),health:100},colliders=[],damage=[],impacts=[];
  const enemy={g:new THREE.Group(),type:'slinger',health:50,maxHealth:50,config:{scale:1,projectileSpeed:20,damage:9,attackRange:15},eliteModifiers:[]};enemy.g.position.set(0,0,10);scene.add(enemy.g);
  const combat={hitWorld:new HitWorld({colliders}),effects:{impact:hit=>impacts.push(hit),burst:point=>impacts.push(point),sound(){}}};let active=true;
  const shots=new EnemyProjectiles({scene,player,combat,hurtPlayer:value=>damage.push(value),active:()=>active});return {scene,player,colliders,damage,impacts,enemy,shots,setActive:value=>active=value};
}

test('enemy shots warn, sweep through slow frames, hit once and stop on walls before the player',()=>{
  const f=fixture();f.shots.fire(f.enemy);f.shots.update(.1);assert.equal(f.damage.length,0);assert.equal(f.shots.shots[0].g.position.z,10);
  f.shots.update(.7);assert.deepEqual(f.damage,[9]);assert.equal(f.shots.shots.length,0);assert.ok(f.impacts.length>0);f.shots.update(1);assert.equal(f.damage.length,1);
  f.colliders.push({x:0,z:4,width:4,depth:.25,minY:0,height:3});f.shots.fire(f.enemy);f.shots.update(1);assert.equal(f.damage.length,1);assert.equal(f.shots.shots.length,0);assert.equal(f.impacts.at(-1).kind,'wall');f.shots.dispose();
});

test('height-aware collision, pause, target snapshot, bounded actors and resource disposal remain consistent',()=>{
  const f=fixture();assert.equal(segmentPlayerHit(new THREE.Vector3(0,6,10),new THREE.Vector3(0,6,-10),f.player.pos),null);
  assert.ok(segmentPlayerHit(new THREE.Vector3(0,.7,10),new THREE.Vector3(0,.7,-10),f.player.pos));
  for(let i=0;i<100;i++)f.shots.fire(f.enemy);assert.equal(f.shots.shots.length,64);
  f.setActive(false);f.shots.update(2);assert.equal(f.shots.shots[0].age,0);assert.equal(f.shots.fire(f.enemy),false);
  f.setActive(true);f.player.pos.x=8;f.shots.update(1);assert.equal(f.damage.length,0,'player dodges a shot aimed at the previous position');
  f.shots.update(4);assert.equal(f.shots.shots.length,0);
  f.shots.fire(f.enemy);f.shots.dispose();assert.equal(f.shots.shots.length,0);assert.equal(f.scene.children.length,1);assert.equal(f.shots.materials.size,0);assert.equal(f.shots.fire(f.enemy),false);
});
