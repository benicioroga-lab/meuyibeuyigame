import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {HitWorld} from '../systems/hit-detection.js';
import {createEnemy,animateEnemy,disposeEnemy} from '../systems/enemies.js';
import {WEAPONS} from '../systems/config.js';

function fixture(){const scene=new THREE.Scene(),enemies=[],colliders=[],props=[],world=new HitWorld({enemies,colliders,props});return {scene,enemies,colliders,props,world,spawn:(x=0,z=8,type='grunt')=>{const e=createEnemy(scene,{x,z,type,seed:1});enemies.push(e);return e;}};}
const origin=new THREE.Vector3(0,1.14,0),forward=new THREE.Vector3(0,0,1);
test('damage ray hits actual visible torso and head, while silhouette gaps and rays above it miss',()=>{
  const f=fixture(),enemy=f.spawn();
  assert.equal(f.world.cast(origin,forward,30)[0].entity,enemy);
  assert.equal(f.world.cast(new THREE.Vector3(0,1.8,0),forward,30)[0].zone,'head');
  assert.equal(f.world.cast(new THREE.Vector3(0,3,0),forward,30).length,0);
  assert.equal(f.world.cast(new THREE.Vector3(0,.18,0),forward,30).length,0,'gap between legs is not a box hit');
  assert.equal(f.world.cast(new THREE.Vector3(1,1,0),forward,30).length,0);
});
test('current transforms are used immediately after moving or animating an enemy',()=>{
  const f=fixture(),enemy=f.spawn();enemy.g.position.x=4;enemy.velocity.set(3,0,0);animateEnemy(enemy,.1,new THREE.PerspectiveCamera());
  assert.equal(f.world.cast(origin,forward,30).length,0);
  assert.equal(f.world.cast(new THREE.Vector3(4,1.14,0),forward,30)[0].entity,enemy);
});
test('cover blocks bullets, including cover thinner than a single movement step',()=>{
  const f=fixture();f.spawn();f.colliders.push({x:0,z:4,width:5,depth:.02,height:4});
  const hits=f.world.cast(origin,forward,100);assert.equal(hits.length,1);assert.equal(hits[0].kind,'wall');assert.ok(Math.abs(hits[0].distance-3.99)<1e-5);
});
test('penetrating shots hit each enemy once and stop at the nearest wall',()=>{
  const f=fixture(),first=f.spawn(),second=f.spawn(0,12);f.spawn(0,18);f.colliders.push({x:0,z:15,width:5,depth:1,height:4});
  const hits=f.world.cast(origin,forward,50,{pierce:5});assert.deepEqual(hits.map(h=>h.kind),['enemy','enemy','wall']);assert.equal(hits[0].entity,first);assert.equal(hits[1].entity,second);
  assert.equal(f.world.cast(origin,forward,50).length,1);
});
test('third person uses the centre of the camera but the muzzle cannot fire through cover',()=>{
  const f=fixture(),enemy=f.spawn(),camera=new THREE.PerspectiveCamera(66,1,.1,200);
  camera.position.set(3,1.14,0);camera.lookAt(0,1.14,8);camera.updateMatrixWorld(true);
  const config={...WEAPONS[0],spread:0},muzzle=new THREE.Vector3(0,1.14,1);
  const clear=f.world.aim(camera,muzzle,config);assert.equal(clear.hits[0].entity,enemy);assert.equal(clear.blocked,false);
  f.colliders.push({x:0,z:3,width:1,depth:.5,height:2});
  const blocked=f.world.aim(camera,muzzle,config);assert.equal(blocked.blocked,true);assert.equal(blocked.hits[0].kind,'wall');
});
test('props use real geometry and breakage exposes the enemy behind them',()=>{
  const f=fixture(),enemy=f.spawn(),prop=new THREE.Mesh(new THREE.BoxGeometry(1,2,1),new THREE.MeshBasicMaterial());prop.position.set(0,1,4);f.scene.add(prop);f.props.push(prop);
  assert.equal(f.world.cast(origin,forward,20)[0].kind,'object');prop.userData.broken=true;prop.removeFromParent();assert.equal(f.world.cast(origin,forward,20)[0].entity,enemy);
});
test('dead actors never intercept shots and disposing one does not remove another shared model',()=>{
  const f=fixture(),first=f.spawn(),second=f.spawn(0,12);first.disabled=true;disposeEnemy(first);
  assert.equal(f.world.cast(origin,forward,30)[0].entity,second);assert.ok(second.g.parent);
});
