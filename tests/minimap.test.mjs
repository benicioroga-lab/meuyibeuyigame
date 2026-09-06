import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {drawTacticalMap} from '../systems/minimap.js';

function fixture(size=240){const labels=[],rotations=[],ctx=new Proxy({fillText:(text,...args)=>labels.push({text,args}),rotate:angle=>rotations.push(angle),createRadialGradient:()=>({addColorStop(){}})},{get:(object,key)=>object[key]||(()=>{})}),canvas={width:size,getContext:()=>ctx};return {canvas,labels,rotations};}
const state=()=>({player:{pos:new THREE.Vector3(0,0,-43),cameraYaw:.5},world:{mapAreas:[],interactions:[],bossZones:[],districts:[]}});

test('active quest remains indicated beyond HUD range with distance and elevation',()=>{
  const f=fixture(),s=state();drawTacticalMap(f.canvas,{...s,quest:{name:'Entrega nas Alturas',target:new THREE.Vector3(14,12,63)}},26);
  assert.ok(f.labels.some(label=>label.text.includes('ALVO')&&label.text.includes('107m')&&label.text.includes('↑12m')));
  assert.deepEqual(f.rotations,[.5],'only the sight cone/player rotate; terrain remains north-up');
});
test('expanded map names the delivery and respects filtered used interactions',()=>{
  const f=fixture(420),s=state();s.world.interactions=[{type:'shop',position:new THREE.Vector3(3,0,-40)}];
  drawTacticalMap(f.canvas,{...s,interactions:[],quest:{name:'Entrega nas Alturas',target:new THREE.Vector3(14,12,63)}},76);
  assert.ok(f.labels.some(label=>label.text.includes('ENTREGA NAS ALTURAS')));assert.ok(!f.labels.some(label=>label.text==='$'));
});
