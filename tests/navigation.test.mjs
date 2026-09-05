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
