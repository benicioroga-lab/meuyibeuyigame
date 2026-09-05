import {test} from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';
import {createExperience} from '../experience.js';
import {WeaponView} from '../systems/combat-effects.js';
import {WEAPONS} from '../systems/config.js';

test('holding right mouse while clicking left fires immediately; releasing left keeps aiming',()=>{
  const nodes=new Map(),windowEvents=new Map(),saved=new Map();
  const makeNode=id=>{const events=new Map(),classes=new Set();return {id,events,hidden:true,dataset:{},style:{setProperty(){}},classList:{add(...xs){xs.forEach(x=>classes.add(x));},remove(...xs){xs.forEach(x=>classes.delete(x));},toggle(){}},querySelector:()=>node(id+' child'),querySelectorAll:()=>[],addEventListener:(name,fn)=>events.set(name,fn),focus(){},setAttribute(){},getClientRects:()=>[{}],childElementCount:1};};
  const node=id=>{if(!nodes.has(id))nodes.set(id,makeNode(id));return nodes.get(id);};
  const setGlobal=(key,value)=>{saved.set(key,Object.getOwnPropertyDescriptor(globalThis,key));Object.defineProperty(globalThis,key,{value,writable:true,configurable:true});};
  setGlobal('document',{getElementById:node,querySelector:node,querySelectorAll:()=>[],addEventListener(){},pointerLockElement:null});
  setGlobal('addEventListener',(name,fn)=>windowEvents.set(name,fn));setGlobal('matchMedia',()=>({matches:false}));setGlobal('localStorage',{getItem:()=>null});
  try{
    const state={running:false,paused:false,coins:250,time:0,upgrades:{bark:0,dash:0},treats:0};
    const player={pos:new THREE.Vector3(),moveVelocity:new THREE.Vector3(),cameraYaw:0,cameraPitch:0,thirdPerson:false,aiming:false,health:100,firing:0,dashCooldown:0};
    let shots=0,shotWasAimed=false;const camera=new THREE.PerspectiveCamera(),dog=new THREE.Group();
    const combat={recoilPitch:0,recoilYaw:0,effects:{shake:0},hitWorld:{surfaces:()=>null},preview:()=>({hits:[]}),fire(){shots++;shotWasAimed=player.aiming;return true;},arsenal:{current:{upgrades:{}},stats:()=>WEAPONS[0]}};
    const noop=()=>{},game={THREE,state,player,keys:{},upgrades:[],scene:new THREE.Scene(),camera,renderer:{},dog,dogParts:{},barkView:new THREE.Group(),roundState:{round:1},ui:{startScreen:node('startScreen'),coins:node('coins'),health:node('health'),healthFill:node('healthFill'),barkCooldown:node('barkCooldown'),treats:node('treats')},
      getCombat:()=>combat,getDog:()=>null,setVolume:noop,setAudioMix:noop,showToast:noop,initAudio:noop,startMusic:noop,resumeMusic:noop,pauseMusic:noop,renderUpgrades:noop,renderMissions:noop,drawMiniMap:noop,updateUI:noop,resize:noop,prestige:noop};
    const experience=createExperience(game);experience.bind();node('startButton').onclick();
    const down=node('game').events.get('mousedown'),up=windowEvents.get('mouseup');
    const mouse=button=>({button,preventDefault(){}});
    down(mouse(2));assert.equal(player.aiming,true);down(mouse(0));assert.equal(shots,1);assert.equal(shotWasAimed,true);
    up(mouse(0));assert.equal(player.aiming,true);up(mouse(2));assert.equal(player.aiming,false);
    // F1 changes perspective independently of ADS, and Tab opens the upgrade drawer.
    const keydown=windowEvents.get('keydown');let prevented=false;
    keydown({code:'F1',preventDefault(){prevented=true;}});assert.equal(player.thirdPerson,true);assert.equal(prevented,true);
    keydown({code:'F1',preventDefault(){}});assert.equal(player.thirdPerson,false);
    keydown({code:'Tab',preventDefault(){}});assert.equal(node('upgradeDrawer').hidden,false);assert.equal(state.paused,true);
  }finally{for(const [key,descriptor]of saved){if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];}}
});

test('weapon model is visible in first person only, with or without aiming',()=>{
  const view=new WeaponView(new THREE.PerspectiveCamera(),new THREE.Group());view.equip(WEAPONS[0]);
  for(const aiming of [false,true]){
    view.update(.016,{active:true,thirdPerson:false,aiming});assert.equal(view.root.visible,true);assert.equal(view.worldRoot.visible,false);
    view.update(.016,{active:true,thirdPerson:true,aiming});assert.equal(view.root.visible,false);assert.equal(view.worldRoot.visible,false);
  }
  view.update(.016,{active:false,thirdPerson:false});assert.equal(view.root.visible,false);view.dispose();
});
