import test from 'node:test';
import assert from 'node:assert/strict';
import {RunDirector} from '../systems/run-director.js';
import {DIFFICULTIES,CHAOS_LEVELS,PERKS,RUN_BALANCE} from '../systems/run-config.js';
import {ENEMY_CONFIG} from '../systems/enemy-config.js';

function harness(options={}){
  const events=[],pending=[];
  const director=new RunDirector({...options,emit:event=>{events.push(event);if(event.type==='spawn')pending.push({roundEnemy:true,runSpawnId:event.spawnId,config:event.stats,elite:event.elite,g:{position:{x:2,y:4,z:6}}});}});
  return {director,events,pending};
}
function clearWave(context){
  let steps=0;
  while(context.director.phase==='combat'&&steps++<20000){context.director.update(.1,{healthRatio:1,ammoRatio:1,enemiesAlive:context.pending.length,dps:80});while(context.pending.length)context.director.onKill(context.pending.shift(),{source:'weapon',damage:42});}
  assert.ok(steps<20000,'a finite wave must always complete');
}

test('the preparation countdown starts exactly one complete wave',()=>{
  const {director,events}=harness();assert.equal(director.start(),true);assert.equal(director.start(),false);
  director.update(3.9);assert.equal(director.phase,'preparation');director.update(.11);
  assert.equal(director.phase,'combat');assert.equal(events.filter(e=>e.type==='round-start').length,1);
  assert.equal(director.remaining,director.target);assert.equal(director.spawnQueue.length,director.target);
});

test('all difficulties and Chaos levels respect every class speed cap',()=>{
  for(const difficulty of DIFFICULTIES)for(const chaos of CHAOS_LEVELS)for(const round of [1,5,30,100,10000]){
    const {director}=harness({difficulty:difficulty.id,chaos:chaos.level});director.startRound(round);
    for(const type of Object.keys(ENEMY_CONFIG)){
      const stats=director.statsFor(type);
      assert.ok(stats.speed<=ENEMY_CONFIG[type].maxSpeed,`${type}/${difficulty.id}/${chaos.level}/${round}`);
      assert.ok(Number.isFinite(stats.hp)&&stats.hp>0);assert.ok(stats.damage>0);
      if(chaos.level>=2)assert.equal(stats.speed,stats.maxSpeed);
    }
  }
});

test('higher risk changes enemy health, aggression, rewards, XP and loot together',()=>{
  const normal=harness({difficulty:'normal'}).director,hard=harness({difficulty:'hard'}).director,chaos=harness({chaos:3}).director;
  for(const d of [normal,hard,chaos])d.startRound();
  const a=normal.statsFor('grunt'),b=hard.statsFor('grunt');
  assert.ok(b.hp>a.hp);assert.ok(b.damage>a.damage);assert.ok(b.speed>a.speed);assert.ok(b.attackCooldown/b.aggression<a.attackCooldown/a.aggression);
  assert.ok(b.reward>a.reward&&b.xp>a.xp);assert.ok(hard.modifiers.lootChance>normal.modifiers.lootChance);
  assert.ok(chaos.statsFor('grunt').speed>=ENEMY_CONFIG.grunt.maxSpeed*.9);assert.ok(chaos.modifiers.lootQuality>normal.modifiers.lootQuality);
  // The normal opener retains the reliable two-hit starter breakpoint.
  assert.equal(a.hp,42);assert.ok(a.speed>ENEMY_CONFIG.grunt.speed);
});

test('unlocked Chaos levels are scoped to meta; malformed settings remain safe',()=>{
  assert.equal(harness({chaos:5,meta:{state:{maxChaos:2}}}).director.chaos,2);
  const {director}=harness({difficulty:'unknown',chaos:NaN,seed:Infinity});assert.equal(director.difficulty,'normal');assert.equal(director.chaos,0);
  director.startRound();assert.ok(director.spawnQueue.every(entry=>ENEMY_CONFIG[entry.enemyType]));
});

test('endless high waves keep HP and actor counts bounded and rotate compositions',()=>{
  const {director}=harness({difficulty:'nightmare',chaos:5,seed:94});director.startRound(10000);
  assert.ok(director.target<=RUN_BALANCE.maxQueuedPerRound);assert.ok(director.concurrentCap<=RUN_BALANCE.maxConcurrent);
  const health=director.statsFor('grunt').hp;director.phase='intermission';director.startRound(10000000);
  assert.equal(director.statsFor('grunt').hp,health);assert.ok(new Set(director.spawnQueue.map(value=>value.enemyType)).size>=6);
  assert.ok(director.mutators.some(value=>value.id==='apocalypse'));
});

test('late resilience protects specials without turning common enemies into sponges',()=>{
  const {director}=harness();director.startRound(30);const grunt=director.statsFor('grunt'),tank=director.statsFor('tank');
  director.phase='intermission';director.startRound(100);const late=director.statsFor('tank');
  assert.equal(director.statsFor('grunt').hp,grunt.hp);assert.ok(late.hp>tank.hp);assert.ok(late.hp<tank.hp*1.5);
  director.phase='intermission';director.startRound(100000);assert.ok(director.statsFor('tank').hp<=Math.round(tank.hp*RUN_BALANCE.lateHealthCap));
});

test('high-round formations create simultaneous pressure while respecting available actor slots',()=>{
  const {director,events}=harness();director.startRound(75);director.update(.5,{healthRatio:1,ammoRatio:1});
  assert.equal(events.filter(event=>event.type==='spawn').length,4);
  director.spawnClock=0;const before=director.spawned;director.update(.1,{enemiesAlive:director.concurrentCap-1});
  assert.equal(director.spawned,before+1);
});

test('spawn concurrency remains bounded even without any kills',()=>{
  const {director,events}=harness({difficulty:'nightmare',chaos:5});director.startRound(80);
  for(let i=0;i<100;i++)director.update(2,{healthRatio:1,ammoRatio:1,enemiesAlive:0});
  assert.equal(events.filter(event=>event.type==='spawn').length,director.concurrentCap);
  assert.ok(director.spawnQueue.length>0);assert.equal(director.remaining,director.target);
});

test('only wave actors advance rounds and kills are idempotent',()=>{
  const context=harness(),{director,events,pending}=context;director.startRound();director.update(.5);
  const enemy=pending.shift(),original=director.remaining;
  const ambient={roundEnemy:false,config:{reward:24},position:{x:1,y:0,z:1}};
  assert.equal(director.onKill(ambient),true);assert.equal(director.remaining,original);
  assert.equal(director.onKill(enemy),true);assert.equal(director.remaining,original-1);
  assert.equal(director.onKill(enemy),false);assert.equal(director.onKill({...enemy}),false);
  assert.equal(events.filter(event=>event.type==='kill').length,2);
  clearWave(context);assert.equal(director.round,2);assert.equal(events.filter(event=>event.type==='round-complete').length,1);
});

test('self-detonating enemies clear the wave without farming resources or combos',()=>{
  const context=harness(),{director,events,pending}=context;director.startRound();director.update(.5);
  const enemy=pending.shift();director.onKill(enemy,{source:'self'});
  assert.equal(director.kills,1);assert.equal(director.totalKills,0);assert.equal(director.combo,0);
  assert.equal(events.filter(event=>['kill','loot-drop','powerup-drop'].includes(event.type)).length,0);
});

test('boss reward belongs to the encounter, and does not clear the active wave',()=>{
  const {director,events}=harness();director.startRound();director.onKill({boss:true,roundEnemy:false,config:{reward:900}},{source:'weapon'});
  assert.equal(director.kills,0);assert.equal(events.filter(event=>['kill','loot-drop','powerup-drop'].includes(event.type)).length,0);
});

test('wave rewards are paid once, with a victory transition and a numbered next round',()=>{
  const context=harness({difficulty:'hard'});context.director.startRound(5);clearWave(context);
  const complete=context.events.find(event=>event.type==='round-complete');assert.equal(complete.round,5);assert.equal(complete.nextRound,6);
  assert.ok(complete.reward>0&&complete.xp>0);assert.ok(complete.slowMotion.scale<1);
  assert.equal(context.director.completeRound(),false);assert.equal(context.events.filter(event=>event.type==='milestone').length,1);
});

test('perk choices pause timers, reject forged choices and apply one option only',()=>{
  const context=harness();context.director.startRound(3);clearWave(context);
  const director=context.director;assert.equal(director.phase,'choice');assert.equal(director.choices.length,3);
  assert.equal(new Set(director.choices.map(value=>value.id)).size,3);
  const time=director.time;director.update(10);assert.equal(director.time,time);
  assert.equal(director.choosePerk('nonexistent'),false);
  const choice=director.choices[0];assert.equal(director.choosePerk(choice.id),true);assert.equal(director.perkLevels[choice.id],1);
  assert.equal(director.choosePerk(choice.id),false);assert.equal(director.phase,'intermission');
});

test('capped builds still receive three useful recovery choices indefinitely',()=>{
  const {director}=harness();for(const perk of Object.values(PERKS))if(Number.isFinite(perk.max))director.perkLevels[perk.id]=perk.max;
  const choices=director.rollChoices();assert.equal(choices.length,3);assert.deepEqual(new Set(choices.map(value=>value.id)),new Set(['supply','payday','patchUp']));
});

test('shop perks charge the shown amount and cannot exceed their limit',()=>{
  const {director}=harness(),wallet={coins:10000};const first=director.getPerkOffers().find(value=>value.id==='quickHands');
  assert.notEqual(first.before,first.after);assert.equal(director.buyPerk('quickHands',wallet),true);assert.equal(wallet.coins,10000-first.price);
  director.buyPerk('quickHands',wallet);director.buyPerk('quickHands',wallet);const balance=wallet.coins;
  assert.equal(director.buyPerk('quickHands',wallet),false);assert.equal(wallet.coins,balance);assert.equal(director.modifiers.reloadTime,.64);
  assert.equal(director.buyPerk('bad-id',wallet),false);
});

test('temporary powerups refresh without stacking forever and expire exactly once',()=>{
  const {director,events}=harness();director.startRound();
  director.activatePowerup('doubleDamage');assert.equal(director.modifiers.damage,2);
  director.update(5);director.activatePowerup('doubleDamage');assert.ok(director.powers.get('doubleDamage').time<=18);
  director.update(18.1);assert.equal(director.modifiers.damage,1);
  assert.equal(events.filter(event=>event.type==='powerup-expired'&&event.id==='doubleDamage').length,1);
  director.activatePowerup('nuke');director.activatePowerup('jackpot');assert.equal(director.powers.size,0);
  assert.ok(events.some(event=>event.type==='powerup-active'&&event.effect==='nuke'&&event.value>0));
});

test('ammo, movement and elemental powerups expose actual combat modifiers',()=>{
  const {director}=harness();director.startRound();
  for(const id of ['infiniteAmmo','frenzy','magnet','overcharge'])assert.equal(director.activatePowerup(id),true);
  assert.equal(director.modifiers.infiniteAmmo,true);assert.equal(director.modifiers.fireRate,1.45);assert.equal(director.modifiers.moveSpeed,1.18);
  assert.equal(director.modifiers.magnet,true);const element=director.modifiers.element;director.update(.3);assert.notEqual(director.modifiers.element,element);
});

test('event modifiers expire and purchasing honors the temporary dealer discount',()=>{
  const {director,events}=harness();director.startRound(10);assert.equal(director.startEvent('armsDealer'),true);
  const offer=director.getPerkOffers()[0],wallet={coins:offer.price};assert.equal(offer.price,Math.round(offer.cost*.8));
  assert.equal(director.buyPerk(offer.id,wallet),true);assert.equal(wallet.coins,0);
  assert.equal(director.startEvent('doubleLoot'),false);director.endEvent();assert.equal(director.modifiers.shopDiscount,1);
  director.startEvent('doubleLoot');assert.equal(director.modifiers.lootChance,2);
  director.update(30);director.update(10.1);assert.equal(director.event,null);assert.equal(director.modifiers.lootChance,1);
  assert.equal(events.filter(event=>event.type==='event-end'&&event.id==='doubleLoot').length,1);
  director.startEvent('redmoon');assert.equal(director.modifiers.enemyAggression,1.2);
  const cooldown=director.statsFor('grunt').attackCooldown;director.endEvent();assert.equal(director.modifiers.enemyAggression,1);assert.equal(director.statsFor('grunt').attackCooldown,cooldown);
});

test('director gives a bounded respite under pressure without secretly reducing damage',()=>{
  const {director,events}=harness();director.startRound(20);for(let i=0;i<7;i++)director.update(1,{healthRatio:1,ammoRatio:1});
  const stats=director.statsFor('grunt');director.onDamage(30);director.update(.2,{healthRatio:.2,ammoRatio:.05,enemiesAlive:10,dps:0});
  assert.ok(events.some(event=>event.type==='rhythm'&&event.phase==='respite'));assert.ok(director.recovery>0&&director.recovery<=RUN_BALANCE.maxRecoveryPause);
  assert.equal(director.statsFor('grunt').damage,stats.damage);assert.equal(director.statsFor('grunt').hp,stats.hp);
});

test('second wind has one charge and requires three completed rounds to recharge',()=>{
  const context=harness(),{director}=context;director.startRound();director.applyPerk('secondWind');assert.equal(director.consumeSecondWind(),true);assert.equal(director.consumeSecondWind(),false);
  clearWave(context);assert.equal(director.secondWindCharges,0);director.startRound();clearWave(context);assert.equal(director.secondWindCharges,0);
  director.startRound();clearWave(context);assert.equal(director.secondWindCharges,1);
});

test('seeded runs reproduce roster and spawn placement independent of frame subdivision',()=>{
  const a=harness({seed:237,runId:'test'}),b=harness({seed:237,runId:'test'});a.director.startRound(12);b.director.startRound(12);
  assert.deepEqual(a.director.spawnQueue,b.director.spawnQueue);
  for(let i=0;i<100;i++)a.director.update(.1);b.director.update(10);
  const shape=e=>({enemyType:e.enemyType,angle:e.angle,distance:e.distance,stats:e.stats,spawnId:e.spawnId});
  assert.deepEqual(a.events.filter(e=>e.type==='spawn').map(shape),b.events.filter(e=>e.type==='spawn').map(shape));
});

test('ending clears temporary state, stops spawning and returns a stable run summary once',()=>{
  const {director,events}=harness();director.startRound(8);director.activatePowerup('frenzy');director.startEvent('blackout');
  const summary=director.end();assert.equal(summary.round,8);assert.equal(director.phase,'dead');assert.equal(director.spawnQueue.length,0);assert.equal(director.powers.size,0);assert.equal(director.event,null);
  const count=events.length;director.update(30);assert.equal(events.length,count);assert.equal(director.end(),null);assert.equal(director.activatePowerup('nuke'),false);
});
