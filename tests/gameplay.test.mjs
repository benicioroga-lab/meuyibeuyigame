import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as THREE from 'three';
import {wavePlan,WEAPONS} from '../systems/config.js';

const experienceSource = readFileSync(new URL('../experience.js',import.meta.url),'utf8').replace(/^export /gm,'');
const appSource = readFileSync(new URL('../app.js',import.meta.url),'utf8').replace(/^import .*;\r?\n/gm,'').replace(/\nsetup\(\);\s*$/,'');

function environment() {
  const nodes=new Map();
  const node=id=>{
    if(!nodes.has(id))nodes.set(id,{id,style:{setProperty(){}},classList:{add(){},remove(){},toggle(){}},textContent:'',hidden:true,querySelectorAll:()=>[],querySelector:()=>node(id+' child'),setAttribute(){},focus(){}});
    return nodes.get(id);
  };
  const context=vm.createContext({THREE,wavePlan,WEAPONS,console,setTimeout:()=>0,clearTimeout(){},performance:{now:()=>0},matchMedia:()=>({matches:false}),localStorage:{getItem:()=>null},
    document:{getElementById:node,querySelector:node,querySelectorAll:()=>[]}});
  vm.runInContext(experienceSource,context);
  const run=code=>vm.runInContext(code,context);
  return {context,run,nodes};
}

function gameEnvironment() {
  const env=environment();vm.runInContext(appSource,env.context);
  env.run(`
    var effects={rewards:[],perks:[],gameOvers:0,announcements:[]};
    experience={reward:n=>effects.rewards.push(n),markPurchased:id=>effects.perks.push(id),damage(){},endGame(){effects.gameOvers++;state.paused=true;},announce:(...args)=>effects.announcements.push(args)};
    scene=new THREE.Scene();dust=()=>{};playSound=()=>{};showToast=()=>{};renderUpgrades=()=>{};updateUI=()=>{};spawnAmmo=()=>{};dogSystem={health:70,training:{stats:()=>({health:70})}};
  `);
  return env;
}

test('settings reject malformed numbers while retaining zero volume',()=>{
  const {run}=environment();
  assert.equal(run('normalizeSettings({volume:0}).volume'),0);
  assert.equal(run('normalizeSettings({sensitivity:Infinity}).sensitivity'),1);
  assert.equal(run('normalizeSettings({cameraDistance:-100}).cameraDistance'),4);
  assert.equal(run('normalizeSettings({sensitivity:20}).sensitivity'),2.5);
  assert.equal(run('normalizeSettings({invertY:"false"}).invertY'),false);
});

test('a pickup grants points once, and collected count stays separate from spending balance',()=>{
  const {run}=gameEnvironment();
  run('var pickup=new THREE.Group();pickup.userData={claimed:false,rare:false,legendary:false,healing:false};scene.add(pickup);collect(pickup);collect(pickup);');
  assert.equal(run('pickup.parent'),null);
  assert.equal(run('state.treats'),1);
  assert.equal(run('state.coins'),260);
  assert.equal(run('effects.rewards.length'),1);
  assert.equal(run('effects.rewards[0]'),10);
});

test('buying a perk deducts its exact price, and insufficient balance cannot buy it again',()=>{
  const {run}=gameEnvironment();
  run('buy("magnet");');
  assert.equal(run('state.coins'),155);
  assert.equal(run('state.upgrades.magnet'),1);
  assert.equal(run('effects.perks[0]'),'magnet');
  run('state.coins=10;buy("magnet");');
  assert.equal(run('state.coins'),10);
  assert.equal(run('state.upgrades.magnet'),1);
  assert.equal(run('effects.perks.length'),1);
});

test('a cleared round rewards once, restores capped health, and waits before the next wave',()=>{
  const {run}=gameEnvironment();
  run('roundState.active=true;roundState.target=7;roundState.kills=6;player.health=95;roundUpdate(.1);');
  assert.equal(run('roundState.round'),1);
  run('recordRoundKill();roundUpdate(.1);');
  assert.equal(run('roundState.round'),2);
  assert.equal(run('state.coins'),395);
  assert.equal(run('player.health'),100);
  assert.equal(run('roundState.cooldown'),12);
  run('roundUpdate(1);');
  assert.equal(run('state.coins'),395);
  assert.equal(run('roundState.cooldown'),11);
});

test('pause and dash protect the player; fatal damage opens the result once',()=>{
  const {run}=gameEnvironment();
  run('state.running=true;state.paused=true;hurtMeyui(20);');
  assert.equal(run('player.health'),100);
  run('state.paused=false;player.dash=.2;hurtMeyui(20);');
  assert.equal(run('player.health'),100);
  run('player.dash=0;player.health=5;hurtMeyui(20);hurtMeyui(20);');
  assert.equal(run('player.health'),0);
  assert.equal(run('effects.gameOvers'),1);
  assert.equal(run('state.paused'),true);
});

