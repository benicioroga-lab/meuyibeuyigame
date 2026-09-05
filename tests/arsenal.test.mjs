import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Arsenal} from '../systems/arsenal.js';
import {WEAPONS,ENEMY_CONFIG,enemyStats,wavePlan,DOG_UPGRADES} from '../systems/config.js';
import {DogTraining} from '../systems/dog.js';

test('every weapon has finite ammunition and its own cadence and reload duration',()=>{
  for(const config of WEAPONS){
    const gun=new Arsenal({random:()=>1});gun.grant(config.id);gun.equip(config.id);gun.tick(1);
    const original=gun.current.magazine+gun.current.reserve;
    for(let i=0;i<config.magazineSize;i++){
      assert.ok(gun.fire({aiming:true}),config.name);assert.equal(gun.fire(),null);
      gun.tick(1/config.fireRate);
    }
    assert.equal(gun.current.magazine,0);assert.equal(gun.fire(),null);
    assert.ok(gun.reloadState);assert.equal(gun.reloadState.total,config.reloadTime);
    const before=gun.current.reserve;gun.tick(config.reloadTime/2);assert.equal(gun.fire(),null);assert.equal(gun.current.reserve,before);
    gun.tick(config.reloadTime/2+.001);
    assert.equal(gun.current.magazine,config.magazineSize);
    assert.equal(gun.current.magazine+gun.current.reserve,original-config.magazineSize);
  }
});
test('partial reload conserves ammo, cannot duplicate it, and empty reserve stays empty',()=>{
  const gun=new Arsenal();gun.current.magazine=3;gun.current.reserve=4;
  assert.equal(gun.reload(),true);assert.equal(gun.reload(),false);
  gun.tick(10);assert.equal(gun.current.magazine,7);assert.equal(gun.current.reserve,0);assert.equal(gun.reload(),false);
  gun.current.magazine=0;for(let i=0;i<10;i++){assert.equal(gun.fire(),null);gun.tick(1);}
  assert.equal(gun.current.magazine+gun.current.reserve,0);
});
test('pause freezes reload and swapping cancels it without transferring ammunition',()=>{
  const gun=new Arsenal();gun.grant('hammer');gun.current.magazine=2;gun.reload();gun.tick(.2);
  const remaining=gun.reloadState.remaining;gun.tick(0);assert.equal(gun.reloadState.remaining,remaining);
  gun.equip('hammer');assert.equal(gun.reloadState,null);gun.tick(3);gun.equip('biscuit');
  assert.equal(gun.current.magazine,2);assert.equal(gun.current.reserve,84);
});
test('switching guns cannot bypass a heavy weapon fire clock',()=>{
  const gun=new Arsenal();gun.grant('hammer');gun.equip('hammer');gun.tick(1);gun.fire();
  gun.equip('biscuit');gun.tick(.17);assert.equal(gun.fire(),null);gun.tick(.61);assert.ok(gun.fire());
});
test('purchases respect unlocks, wallet, ownership and maximum upgrades',()=>{
  const gun=new Arsenal(),wallet={coins:1000};
  assert.equal(gun.buy('hammer',wallet,3),false);assert.equal(wallet.coins,1000);
  assert.equal(gun.buy('hammer',wallet,4),true);assert.equal(wallet.coins,50);
  assert.equal(gun.buy('hammer',wallet,4),false);assert.equal(gun.buy('zero',wallet,12),false);
  wallet.coins=10000;const ammo=gun.current.magazine+gun.current.reserve;
  for(let i=0;i<3;i++)assert.equal(gun.upgrade('damage',wallet),true);
  const balance=wallet.coins;assert.equal(gun.upgrade('damage',wallet),false);assert.equal(wallet.coins,balance);
  assert.equal(gun.current.magazine+gun.current.reserve,ammo);
  assert.equal(gun.nextStats('damage'),null);
});
test('reserve refills and pickups cannot exceed their capacity or charge a full inventory',()=>{
  const gun=new Arsenal(),wallet={coins:1000};gun.addAmmo(100);
  assert.equal(gun.current.reserve,gun.stats().maxReserve);assert.equal(gun.refill(wallet,1),false);assert.equal(wallet.coins,1000);
  gun.current.reserve=0;assert.equal(gun.refill(wallet,1),true);assert.equal(wallet.coins,962);assert.equal(gun.current.magazine,12);
});
test('enemy speed and HP stay capped across thousands of rounds; every variant unlocks before spawning',()=>{
  for(const [type,base] of Object.entries(ENEMY_CONFIG)){
    let previous=enemyStats(type,1);
    for(let round=2;round<=2000;round++){
      const stats=enemyStats(type,round);assert.ok(stats.speed<=base.maxSpeed);assert.ok(stats.speed>=previous.speed);
      assert.ok(stats.hp>=previous.hp&&stats.hp<=Math.ceil(base.hp*2.5));previous=stats;
    }
    assert.equal(enemyStats(type,100).hp,enemyStats(type,2000).hp);
  }
  for(let round=1;round<=100;round++){const wave=wavePlan(round);assert.equal(wave.target,wave.types.length);assert.ok(wave.target<=31);assert.equal(wave.special,round%5===0);for(const type of wave.types)assert.ok(ENEMY_CONFIG[type].unlockRound<=round);}
  assert.equal(wavePlan(1).target,7);
});
test('Faro upgrades expose accurate previews, cap their level and gate elemental stages',()=>{
  const training=new DogTraining(),wallet={coins:100000};
  assert.equal(training.buy('element',wallet,2),false);assert.equal(training.buy('element',wallet,3),true);
  assert.equal(training.buy('element',wallet,6),false);assert.equal(training.buy('element',wallet,7),true);
  assert.equal(training.buy('element',wallet,10),false);assert.equal(training.buy('element',wallet,11),true);
  for(const [id,config] of Object.entries(DOG_UPGRADES)){
    while(training.levels[id]<config.max){const next=training.next(id);assert.ok(training.buy(id,wallet,100));assert.deepEqual(training.stats(),next);}
    const balance=wallet.coins;assert.equal(training.buy(id,wallet,100),false);assert.equal(balance,wallet.coins);
  }
  const stats=training.stats();assert.ok(stats.speed<=8);assert.ok(stats.attackCooldown>=.65);assert.ok(stats.damage>14);assert.equal(stats.targets,3);assert.equal(stats.element,3);
});
