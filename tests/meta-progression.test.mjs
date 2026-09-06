import test from 'node:test';
import assert from 'node:assert/strict';
import {MetaProgression,META_UPGRADES} from '../systems/meta-progression.js';

const storage=()=>{const values=new Map();return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),values};};
test('progress is saved only to the designated game key and survives reload',()=>{
  const store=storage(),meta=new MetaProgression({storage:store,key:'game-test',runId:'first'});
  meta.award('boss',{bossId:'gatekeeper',encounterId:'arena-1',round:5});meta.record('chest',2);meta.endRun({completedRound:7,score:960});
  const restored=new MetaProgression({storage:store,key:'game-test'});
  assert.equal(store.values.size,1);assert.equal(restored.state.stats.bosses,1);assert.equal(restored.state.stats.chests,2);assert.equal(restored.state.stats.bestRound,7);assert.equal(restored.state.stats.bestScore,960);assert.equal(restored.state.shards,5);
});
test('duplicate boss, milestone and end-run callbacks cannot award twice',()=>{
  const meta=new MetaProgression({storage:null,runId:'once'}),boss={bossId:'gatekeeper',encounterId:'fight1',round:5};
  assert.equal(meta.award('boss',boss),2);assert.equal(meta.award('boss',boss),0);assert.equal(meta.state.stats.bosses,1);
  assert.equal(meta.award('milestone',{round:5}),1);assert.equal(meta.award('milestone',{round:5}),0);assert.equal(meta.award('milestone',{round:6}),0);
  meta.endRun({round:5});meta.endRun({round:5});assert.equal(meta.state.stats.runs,1);
  meta.beginRun({runId:'new-run'});assert.equal(meta.award('boss',boss),2);assert.equal(meta.state.stats.bosses,2);
});
test('storage corruption, unavailable storage, and older saves are handled safely',()=>{
  const store=storage();store.setItem('bad','{"version":');assert.doesNotThrow(()=>new MetaProgression({storage:store,key:'bad'}));
  store.setItem('old',JSON.stringify({version:1,crystals:8,bestRound:13}));const migrated=new MetaProgression({storage:store,key:'old'});assert.equal(migrated.state.shards,8);assert.equal(migrated.state.stats.bestRound,13);assert.equal(migrated.state.version,2);
  const blocked=new MetaProgression({storage:{getItem(){throw Error('blocked');},setItem(){throw Error('blocked');}}});assert.doesNotThrow(()=>blocked.award('milestone',{round:5}));assert.equal(blocked.state.shards,1);assert.equal(blocked.storageAvailable,false);blocked.load();assert.equal(blocked.state.shards,1);
});
test('invalid stored fields are bounded and cannot activate unknown unlocks or loadouts',()=>{
  const store=storage();store.setItem('bad',JSON.stringify({shards:-100,upgrades:{chaos:999,supplies:999,conditioning:-20,unknown:5},achievements:['unknown','first_boss','first_boss'],loadout:{weaponId:'horizon',character:'root'},stats:{kills:-2,bestRound:'not a number'}}));
  const meta=new MetaProgression({storage:store,key:'bad'});assert.equal(meta.state.shards,0);assert.equal(meta.state.maxChaos,5);assert.equal(meta.state.upgrades.supplies,2);assert.equal(meta.state.upgrades.conditioning,0);assert.equal(meta.state.upgrades.unknown,undefined);assert.deepEqual(meta.state.achievements,['first_boss']);assert.equal(meta.state.loadout.weaponId,'biscuit');assert.equal(meta.state.stats.bestRound,0);
});
test('permanent purchases unlock real loadout options, preserve currency, and cap passive power',()=>{
  const meta=new MetaProgression({storage:null});assert.equal(meta.purchase('unknown'),false);assert.equal(meta.purchase('horizon'),false);assert.equal(meta.selectLoadout({weaponId:'horizon'}),false);meta.state.shards=1000;
  for(const [id,config] of Object.entries(META_UPGRADES))for(let i=0;i<config.max;i++)assert.equal(meta.purchase(id),true,id);
  const balance=meta.state.shards;assert.equal(meta.purchase('supplies'),false);assert.equal(meta.state.shards,balance);assert.equal(meta.selectLoadout({weaponId:'horizon',attachmentId:'cryocell',character:'keeper',skin:'copper'}),true);
  const bonuses=meta.getRunBonuses();assert.equal(bonuses.startingWeaponId,'horizon');assert.equal(bonuses.startingAttachmentId,'cryocell');assert.equal(bonuses.skinColor,'#d49362');assert.equal(bonuses.dogHealthMultiplier,1.2);assert.ok(bonuses.maxHealthMultiplier<=1.2);assert.ok(bonuses.startingAmmoMultiplier<=1.2);assert.equal(meta.getLoadoutOptions().maxChaos,5);assert.equal(meta.getLoadoutOptions().difficulties.length,5);
});
test('achievements and run challenges reward qualifying play only once',()=>{
  const meta=new MetaProgression({storage:null,runId:'achievement'});assert.equal(meta.award('challenge',{challengeId:'clean'}),0);
  meta.record('roundComplete',{round:5,damageTaken:1});assert.equal(meta.runChallenges.has('clean'),false);
  meta.record('roundComplete',{round:6,damageTaken:0});assert.equal(meta.runChallenges.has('clean'),true);const cleanReward=meta.state.shards;
  meta.record('roundComplete',{round:7,damageTaken:0});assert.equal(meta.state.shards,cleanReward);
  meta.record('kill',{amount:25,headshot:true});assert.ok(meta.state.achievements.includes('precision'));meta.record('kill',{amount:50,source:'dog'});assert.ok(meta.state.achievements.includes('good_dog'));assert.ok(meta.runChallenges.has('partner'));
  meta.record('chest',3);assert.ok(meta.runChallenges.has('scavenger'));const saved=meta.state.shards;meta.checkAchievements();assert.equal(meta.state.shards,saved);
  meta.beginRun({runId:'next'});assert.equal(meta.run.headshots,0);assert.equal(meta.runChallenges.size,0);assert.ok(meta.state.achievements.includes('precision'));
});
