import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {Navigation} from '../systems/navigation.js';

test('pursuit routes around a wall without entering its collision volume',()=>{
  const nav=new Navigation([{x:0,z:5,width:7,depth:2,height:6}]);
  const entity={g:new THREE.Group(),seed:2,velocity:new THREE.Vector3()},target=new THREE.Vector3(0,0,12);
  for(let frame=0;frame<1200;frame++){nav.move(entity,target,3,1/60,.45);assert.equal(nav.blocked(entity.g.position.x,entity.g.position.z,.44),false);}
  assert.ok(entity.g.position.distanceTo(target)<1,entity.g.position.toArray().join(','));
});
test('spawn correction finds free ground and closed corners cannot be crossed diagonally',()=>{
  const nav=new Navigation([{x:0,z:0,width:4,depth:4,height:3},{x:4,z:4,width:4,depth:4,height:3}]);
  const position=nav.freePosition(new THREE.Vector3(0,0,0),.5);assert.equal(nav.blocked(position.x,position.z,.5),false);
  assert.equal(nav.clearLine(new THREE.Vector3(0,0,4),new THREE.Vector3(4,0,0),.5),false);
});
test('movement distance is bounded by configured speed even with a large simulation step',()=>{
  const nav=new Navigation([]),entity={g:new THREE.Group(),seed:0},target=new THREE.Vector3(30,0,30);
  const before=entity.g.position.clone();nav.move(entity,target,4,.5,.4);assert.ok(entity.g.position.distanceTo(before)<=2.00001);
});

test('frame budget staggers blocked-route searches while preserving direct movement',()=>{
  const nav=new Navigation([{x:0,z:5,width:7,depth:2,height:6}]),a={g:new THREE.Group(),seed:0},b={g:new THREE.Group(),seed:1},direct={g:new THREE.Group(),seed:2},target=new THREE.Vector3(0,0,12);
  b.g.position.x=1;direct.g.position.x=15;nav.beginFrame();nav.move(a,target,3,1/60,.4);nav.move(b,target,3,1/60,.4);nav.move(direct,new THREE.Vector3(15,0,12),3,1/60,.4);
  assert.ok(a.path?.length);assert.equal(b.path,undefined);assert.ok(direct.g.position.z>0);assert.equal(nav.replansThisFrame,1);
  nav.beginFrame();nav.move(b,target,3,1/60,.4);assert.ok(b.path?.length);
});

test('stable goals reuse routes and moved endpoints keep collision-safe cached corners',()=>{
  const nav=new Navigation([{x:0,z:5,width:7,depth:2,height:6}]),start=new THREE.Vector3(),target=new THREE.Vector3(0,0,12);
  const original=nav.path(start,target,.4),again=nav.path(start,new THREE.Vector3(.8,0,12),.4);assert.ok(nav.routes.size>0);
  let prior=start;for(const point of again){assert.equal(nav.clearLine(prior,point,.4),true);prior=point;}assert.ok(prior.distanceTo(new THREE.Vector3(.8,0,12))<.001);
  original[0].set(200,0,200);const safe=nav.path(start,target,.4);assert.ok(safe[0].x<10,'entity path must not mutate shared cache');
  const entity={g:new THREE.Group(),seed:0};nav.move(entity,target,0,1/60,.4);const path=entity.path;for(let i=0;i<180;i++)nav.move(entity,target,0,1/60,.4);assert.equal(entity.path,path,'no search every second for a stationary goal');
});
