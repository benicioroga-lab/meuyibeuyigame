import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import * as THREE from 'three';
import {normalizeSettings} from '../experience.js';
import {RunDirector} from '../systems/run-director.js';

// Exercise the application's actual orchestration functions without launching WebGL.
// Rendering and audio are adapters; damage, recovery and wallet mutation remain the shipped code.
const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
function applicationFunction(name){
  const start=app.indexOf(`function ${name}(`);assert.ok(start>=0,`Missing application function ${name}`);
  const next=app.indexOf('\nfunction ',start+1);return app.slice(start,next<0?app.length:next);
}
function fixture(){
  const calls={rewards:[],deaths:0,damage:0},state={running:true,paused:false,coins:250,earned:0,treats:0,upgrades:{armor:0,magnet:0}},player={health:100,maxHealth:100,damageCooldown:0,dash:0,shield:0,downed:false};
  const director=new RunDirector(),context=vm.createContext({THREE,Math,state,player,director,roundDamage:0,bonuses:{maxHealthMultiplier:1},
    active:()=>state.running&&!state.paused,modifiers:()=>director.modifiers,combat:{arsenal:{setModifiers(){}}},
    upgrades:[{id:'magnet',base:95}],shop:{render(){}},updateUI(){},toast(){},playSound(){},meta:{record(){}},
    companion:{onPlayerDowned:()=>false},experience:{reward:value=>calls.rewards.push(value),markPurchased(){},damage:()=>calls.damage++,announce(){},endGame(){calls.deaths++;state.paused=true;}}});
  vm.runInContext(['coins','buy','hurt','revive','refreshStats'].map(applicationFunction).join('\n'),context);
  return {state,player,director,calls,run:code=>vm.runInContext(code,context)};
}

test('settings reject malformed numbers, retain zero volumes and allow disabling damage numbers',()=>{
  assert.equal(normalizeSettings({volume:0}).volume,0);assert.equal(normalizeSettings({musicVolume:0}).musicVolume,0);
  assert.equal(normalizeSettings({sensitivity:Infinity}).sensitivity,1);assert.equal(normalizeSettings({cameraDistance:-100}).cameraDistance,4);
  assert.equal(normalizeSettings({sensitivity:20}).sensitivity,2.5);assert.equal(normalizeSettings({invertY:'false'}).invertY,false);assert.equal(normalizeSettings({damageNumbers:false}).damageNumbers,false);
});
test('the application wallet animates only the real transaction and separates lifetime earnings from spending',()=>{
  const f=fixture();f.run('coins(24);coins(-50);coins(NaN)');assert.equal(f.state.coins,224);assert.equal(f.state.earned,24);assert.equal(f.state.treats,1);assert.deepEqual(f.calls.rewards,[24,-50]);
});
test('perk purchasing respects its exact price, an empty wallet and maximum level',()=>{
  const f=fixture();f.run('buy("magnet")');assert.equal(f.state.coins,155);assert.equal(f.state.upgrades.magnet,1);assert.deepEqual(f.calls.rewards,[-95]);
  f.state.coins=0;f.run('buy("magnet")');assert.equal(f.state.upgrades.magnet,1);f.state.coins=10000;f.state.upgrades.magnet=5;f.run('buy("magnet")');assert.equal(f.state.coins,10000);
});
test('pause, dash and the damage cooldown prevent duplicate damage; fatal damage opens the result once',()=>{
  const f=fixture();f.state.paused=true;f.run('hurt(20)');assert.equal(f.player.health,100);f.state.paused=false;f.player.dash=.2;f.run('hurt(20)');assert.equal(f.player.health,100);
  f.player.dash=0;f.run('hurt(20);hurt(20)');assert.equal(f.player.health,80);assert.equal(f.calls.damage,1);
  f.player.damageCooldown=0;f.player.health=5;f.run('hurt(20);hurt(20)');assert.equal(f.player.health,0);assert.equal(f.calls.deaths,1);assert.equal(f.state.paused,true);
});
test('health perks change maximum HP coherently, shields absorb first and recovery uses the upgraded maximum',()=>{
  const f=fixture();f.player.health=80;f.director.perkLevels.ironSkin=2;f.run('refreshStats()');assert.equal(f.player.maxHealth,136);assert.equal(f.player.health,116);
  f.player.shield=10;f.run('hurt(20)');assert.equal(f.player.shield,0);assert.ok(Math.abs(f.player.health-107.6)<1e-8);
  f.run('revive(.4)');assert.equal(f.player.health,54);assert.equal(f.player.damageCooldown,3);assert.equal(f.player.downed,false);
});
