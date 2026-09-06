import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Arsenal} from '../systems/arsenal.js';
import {LOOT_WEAPONS,RARITIES,ATTACHMENTS,INVENTORY_LIMIT,FORGE_MAX_TIER} from '../systems/loot-config.js';
import {rollWeapon,stockWeapon,computeWeaponStats,compareWeapons,chooseRarity,seededRandom} from '../systems/weapon-rolls.js';

const rich=()=>({coins:10000000});
const fireReady=(arsenal,options)=>{arsenal.tick(10);return arsenal.fire(options);};
const withPerk=perk=>{const roll=rollWeapon({baseId:'biscuit',rarity:'legendary',seed:123});roll.perk=perk;roll.attachments={};return roll;};

test('rolls are reproducible, have distinct identities and never scale infinitely with round',()=>{
  const options={baseId:'popcorn',round:25,difficulty:'nightmare',chaos:5,seed:'my-run-42',rarity:'epic'};
  assert.deepEqual(rollWeapon(options),rollWeapon(options));
  assert.notDeepEqual(rollWeapon(options),rollWeapon({...options,seed:'my-run-43'}));
  for(const rarity of Object.keys(RARITIES))for(let seed=0;seed<50;seed++){
    const roll=rollWeapon({rarity,round:10000,seed}),stats=computeWeaponStats(roll);
    assert.equal(stats.rarity,rarity);assert.ok(stats.rarityName&&stats.raritySymbol);
    assert.ok(stats.damage>0&&stats.damage<450);assert.ok(stats.fireRate>=.35&&stats.fireRate<=32);
    assert.ok(stats.magazineSize>=2&&stats.magazineSize<=120);assert.ok(stats.criticalChance<=.8);
    assert.ok(Object.keys(roll.attachments).length<=stats.attachmentSlots);
    const earlier=computeWeaponStats({...roll,level:1});assert.ok(stats.damage>=earlier.damage);assert.ok(stats.damage<=Math.ceil(earlier.damage*1.32)+1);
  }
});
test('higher challenge improves rarity odds with seeded samples, without making mythics guaranteed',()=>{
  const order=Object.keys(RARITIES),normal=seededRandom(91),hard=seededRandom(91);let basic=0,chaos=0,mythics=0;
  for(let i=0;i<10000;i++){
    basic+=order.indexOf(chooseRarity({random:normal}));
    const value=chooseRarity({difficulty:'nightmare',chaos:5,round:30,random:hard});chaos+=order.indexOf(value);mythics+=value==='mythic';
  }
  assert.ok(chaos>basic*1.35);assert.ok(mythics>0&&mythics<1000);
});
test('duplicate base weapons retain independent rolls, ammo and upgrades',()=>{
  const arsenal=new Arsenal(),roll=rollWeapon({baseId:'biscuit',rarity:'rare',seed:8});
  const first=arsenal.addLoot(roll),second=arsenal.addLoot(roll);assert.notEqual(first,second);
  arsenal.equip(first);fireReady(arsenal);arsenal.upgrade('damage',rich());
  assert.notEqual(arsenal.current.magazine,arsenal.inventory.get(second).magazine);
  assert.equal(arsenal.inventory.get(second).upgrades.damage,0);
  assert.equal(roll.uid,first);assert.equal(roll.tier,0);
});
test('all weapon families use finite ammunition with tactical and empty reload distinctions',()=>{
  assert.ok(LOOT_WEAPONS.some(weapon=>weapon.family==='shotgun'));
  assert.ok(LOOT_WEAPONS.some(weapon=>weapon.family==='sniper'));
  for(const weapon of LOOT_WEAPONS){
    const arsenal=new Arsenal();arsenal.grant(weapon.id);arsenal.equip(weapon.id);arsenal.tick(1);
    const config=arsenal.stats(),shot=arsenal.fire({aiming:true});assert.ok(shot);assert.equal(shot.pellets,weapon.pellets);
    arsenal.reload();assert.equal(arsenal.reloadState.kind,'tactical');assert.equal(arsenal.reloadState.total,config.reloadTime);
    arsenal.cancelReload();arsenal.current.magazine=0;arsenal.reload();assert.equal(arsenal.reloadState.kind,'empty');assert.ok(arsenal.reloadState.total>config.reloadTime);
    const ammo=arsenal.current.reserve;arsenal.tick(10);assert.equal(arsenal.current.magazine+arsenal.current.reserve,ammo);
  }
});
test('attachments have tradeoffs, clear previews and preserve ammunition during a magazine swap',()=>{
  const arsenal=new Arsenal(),wallet=rich(),before=arsenal.stats(),preview=arsenal.previewAttachment('magazine','extended');
  assert.ok(preview.magazineSize>before.magazineSize);assert.ok(preview.reloadTime>before.reloadTime);
  const total=arsenal.current.magazine+arsenal.current.reserve;
  assert.ok(arsenal.installAttachment('magazine','extended',wallet));assert.equal(arsenal.stats().magazineSize,preview.magazineSize);
  assert.equal(arsenal.current.magazine+arsenal.current.reserve,total);
  arsenal.reload();arsenal.tick(10);
  assert.ok(arsenal.installAttachment('magazine','quickmag',wallet));
  assert.equal(arsenal.current.magazine+arsenal.current.reserve,total);assert.ok(arsenal.current.magazine<=arsenal.stats().magazineSize);
  assert.equal(arsenal.attachmentStash.size,1);assert.equal([...arsenal.attachmentStash.values()][0].attachmentId,'extended');
  const comparisons=compareWeapons(before,arsenal.stats());assert.equal(comparisons.find(item=>item.key==='reloadTime').better,true);
});
test('attachment drops can be installed and swapped without free copies, with transactional wallet checks',()=>{
  const arsenal=new Arsenal(),id=arsenal.addAttachment('dot','agulha');
  assert.ok(arsenal.equipAttachment(id));assert.equal(arsenal.attachmentStash.size,0);assert.equal(arsenal.equipAttachment(id),false);
  assert.equal(arsenal.installAttachment('scope','marksman'),false);
  const balance={coins:10};assert.equal(arsenal.installAttachment('scope','marksman',balance),false);assert.equal(balance.coins,10);
  assert.equal(arsenal.installAttachment('barrel','compensator',rich()),false,'common has one slot; occupied optics can still be replaced');
  assert.ok(arsenal.installAttachment('scope','marksman',rich()));assert.equal(arsenal.attachmentStash.size,1);
  assert.equal(arsenal.current.roll.attachments.scope.id,'marksman');
});
test('burst consumes one round per actual subshot, persists without trigger and cannot bypass shared cadence',()=>{
  const arsenal=new Arsenal(),wallet=rich();assert.ok(arsenal.installAttachment('receiver','burst',wallet));
  const start=arsenal.current.magazine,first=arsenal.fire();assert.equal(first.burstCount,3);assert.equal(arsenal.current.magazine,start-1);
  assert.equal(arsenal.fire({burstFollowup:true}),null);arsenal.tick(.075);
  assert.equal(arsenal.fire(),null);assert.ok(arsenal.fire({burstFollowup:true}));arsenal.tick(.075);
  assert.ok(arsenal.fire({burstFollowup:true}));assert.equal(arsenal.current.magazine,start-3);assert.equal(arsenal.burstRemaining,0);
  assert.equal(arsenal.fire(),null);
  arsenal.tick(10);arsenal.fire();arsenal.grant('hammer');arsenal.equip('hammer');arsenal.tick(.33);
  assert.equal(arsenal.fire(),null,'holstering cannot cancel burst recovery');
});
test('burst with a nearly empty magazine never schedules free followups',()=>{
  const arsenal=new Arsenal();arsenal.installAttachment('receiver','burst',rich());arsenal.current.magazine=2;
  assert.ok(arsenal.fire());assert.equal(arsenal.burstRemaining,1);arsenal.tick(.075);assert.ok(arsenal.fire({burstFollowup:true}));
  assert.equal(arsenal.burstRemaining,0);assert.equal(arsenal.current.magazine,0);arsenal.tick(10);assert.equal(arsenal.fire({burstFollowup:true}),null);
});
test('temporary infinite ammo neither duplicates ammo nor continues after the buff expires',()=>{
  const arsenal=new Arsenal(),ammo=arsenal.current.magazine+arsenal.current.reserve;
  arsenal.setModifiers({infiniteAmmo:true});for(let i=0;i<20;i++)assert.ok(fireReady(arsenal));
  assert.equal(arsenal.current.magazine+arsenal.current.reserve,ammo);
  arsenal.current.magazine=0;assert.ok(fireReady(arsenal));assert.equal(arsenal.current.magazine,0);
  arsenal.setModifiers({});assert.equal(fireReady(arsenal),null);assert.ok(arsenal.reloadState);
});
test('damage, cadence, crit and reserve modifiers are composed once in HUD and shots',()=>{
  const arsenal=new Arsenal(),base=arsenal.stats();arsenal.setModifiers({damage:2,fireRate:1.5,reloadTime:.7,criticalChance:.2,criticalMultiplier:1.2,reserveAmmo:1.5});
  const config=arsenal.stats(),shot=arsenal.fire();assert.equal(config.damage,base.damage*2);assert.equal(shot.damage,config.damage);
  assert.ok(Math.abs(config.fireRate-base.fireRate*1.5)<1e-8);assert.equal(config.maxReserve,base.maxReserve*1.5);
  assert.equal(config.criticalChance,base.criticalChance+.2);assert.ok(config.reloadTime<base.reloadTime);
});
test('legendary mechanics trigger on exact shots and kill effects are temporary',()=>{
  const arsenal=new Arsenal({random:()=>0}),last=arsenal.addLoot(withPerk('last_word'));arsenal.equip(last);arsenal.current.magazine=1;
  const damage=arsenal.stats().damage;assert.equal(fireReady(arsenal).damage,damage*4);
  const fifth=arsenal.addLoot(withPerk('fifth_arc'));arsenal.equip(fifth);
  for(let i=1;i<=5;i++){const shot=fireReady(arsenal);assert.equal(Boolean(shot.empowered),i===5);if(i===5)assert.equal(shot.chainTargets,4);}
  const echo=arsenal.addLoot(withPerk('echo'));arsenal.equip(echo);const count=arsenal.current.magazine;assert.equal(fireReady(arsenal).bonusShots,1);assert.equal(arsenal.current.magazine,count-1);
  const tempo=arsenal.addLoot(withPerk('tempo'));arsenal.equip(tempo);const rate=arsenal.stats().fireRate;
  for(let i=0;i<10;i++)arsenal.onKill({weaponId:tempo});assert.equal(arsenal.current.tempoStacks,5);assert.ok(arsenal.stats().fireRate>rate);arsenal.tick(5.1);assert.equal(arsenal.stats().fireRate,rate);
});
test('kill reload transfers actual reserve, never creates ammunition or uses another weapon reserve',()=>{
  const arsenal=new Arsenal();arsenal.grant('hammer');arsenal.setModifiers({killReload:.25});arsenal.current.magazine=2;arsenal.current.reserve=2;
  arsenal.onKill({weaponId:'biscuit'});assert.equal(arsenal.current.magazine,4);assert.equal(arsenal.current.reserve,0);
  arsenal.onKill({weaponId:'biscuit'});assert.equal(arsenal.current.magazine,4);assert.equal(arsenal.inventory.get('hammer').reserve,42);
});
test('forge reaches five exact previews, unlocks behavior and never takes money past its cap',()=>{
  const arsenal=new Arsenal(),wallet=rich();let previousCost=0;
  for(let tier=1;tier<=FORGE_MAX_TIER;tier++){
    const next=arsenal.previewForge(),cost=arsenal.forgeCost();assert.ok(cost>previousCost);previousCost=cost;
    assert.ok(arsenal.forge(wallet));assert.equal(arsenal.stats().damage,next.damage);assert.equal(arsenal.stats().reloadTime,next.reloadTime);assert.equal(arsenal.stats().tier,tier);
  }
  assert.ok(arsenal.stats().perk);assert.equal(arsenal.forgeCost(),null);const coins=wallet.coins;assert.equal(arsenal.forge(wallet),false);assert.equal(wallet.coins,coins);
});
test('rerolls have rising costs, preserve the instance and gate legendary perks',()=>{
  const arsenal=new Arsenal({random:()=>.75}),wallet=rich(),id=arsenal.currentId;
  assert.equal(arsenal.rerollCost('perk'),null);assert.equal(arsenal.reroll('perk',wallet),false);
  const cost=arsenal.rerollCost('stat');assert.ok(arsenal.reroll('stat',wallet));assert.ok(arsenal.rerollCost('stat')>cost);
  const old=arsenal.current.roll.element;assert.ok(arsenal.reroll('element',wallet));assert.notEqual(arsenal.current.roll.element,old);assert.equal(arsenal.currentId,id);
  assert.ok(arsenal.reroll('attachment',wallet));assert.equal(Object.keys(arsenal.current.roll.attachments).length,1);
});
test('inventory cap and favorite safeguard protect loot without charging failed purchases',()=>{
  const arsenal=new Arsenal(),wallet=rich();for(let i=1;i<INVENTORY_LIMIT;i++)assert.ok(arsenal.addLoot(rollWeapon({seed:i})));
  assert.equal(arsenal.addLoot(rollWeapon({seed:99})),false);const coins=wallet.coins;assert.equal(arsenal.buy('hammer',wallet,100),false);assert.equal(wallet.coins,coins);
  const selected=[...arsenal.inventory.keys()][1];arsenal.toggleFavorite(selected);assert.equal(arsenal.salvage(selected,wallet),false);
  arsenal.toggleFavorite(selected);const value=arsenal.salvage(selected,wallet);assert.ok(value>0);assert.equal(wallet.coins,coins+value);assert.equal(arsenal.inventory.size,INVENTORY_LIMIT-1);
});
test('inspection cancels on shooting, pauses without ticking, and reload cancel loses no rounds',()=>{
  const arsenal=new Arsenal();assert.ok(arsenal.inspect());assert.equal(arsenal.animationState.type,'inspect');arsenal.tick(0);assert.equal(arsenal.animationState.remaining,1.5);
  assert.ok(arsenal.fire());assert.equal(arsenal.animationState,null);const ammo=arsenal.current.magazine+arsenal.current.reserve;
  arsenal.reload();arsenal.tick(.4);assert.equal(arsenal.inspect(),false);arsenal.cancelReload();arsenal.tick(10);assert.equal(arsenal.current.magazine+arsenal.current.reserve,ammo);
});
test('starter equipment cannot be sold and reacquired to generate endless money',()=>{
  const arsenal=new Arsenal(),wallet=rich();arsenal.grant('hammer');const coins=wallet.coins;
  assert.equal(arsenal.salvageValue('biscuit'),0);assert.equal(arsenal.salvage('biscuit',wallet),false);
  assert.equal(arsenal.currentId,'biscuit');assert.equal(wallet.coins,coins);assert.equal(arsenal.buy('biscuit',wallet,1),false);
  const found=arsenal.addLoot(rollWeapon({baseId:'biscuit',seed:88}));assert.ok(arsenal.salvage(found,wallet)>0,'found copies remain useful loot');
});
test('element rerolls affect the actual weapon even when it has elemental attachments',()=>{
  const arsenal=new Arsenal({random:()=>.6}),wallet=rich();assert.ok(arsenal.installAttachment('ammo','shockcell',wallet));
  assert.equal(arsenal.stats().element,'shock');assert.ok(arsenal.reroll('element',wallet));assert.notEqual(arsenal.stats().element,'shock');
  assert.ok(arsenal.installAttachment('ammo','cryocell',wallet));assert.equal(arsenal.stats().element,'cryo');
});
test('expired reserve bonuses cannot retain ammunition beyond the restored capacity',()=>{
  const arsenal=new Arsenal(),wallet=rich(),base=arsenal.stats().maxReserve;
  arsenal.setModifiers({reserveAmmo:2});arsenal.tick(0);arsenal.refill(wallet,1);assert.equal(arsenal.current.reserve,base*2);
  arsenal.setModifiers({});arsenal.tick(0);assert.equal(arsenal.current.reserve,base);
});
test('refinement opens after Forge V, preserves its preview and remains useful over hundreds of purchases',()=>{
  const arsenal=new Arsenal(),wallet={coins:1e15};assert.equal(arsenal.refineCost(),null);assert.equal(arsenal.previewRefine(),null);assert.equal(arsenal.refine(wallet),false);
  for(let tier=0;tier<5;tier++)arsenal.forge(wallet);
  const initial=arsenal.stats().damage;let previousCost=0,previousBonus=0,firstGain=0,lastGain=0;
  for(let level=1;level<=500;level++){
    const before=arsenal.stats(),next=arsenal.previewRefine(),cost=arsenal.refineCost();
    assert.ok(cost>previousCost);assert.ok(next.damage>before.damage);assert.equal(next.refinement,level);
    arsenal.current.magazine=1;arsenal.current.reserve=0;const coins=wallet.coins;
    assert.ok(arsenal.refine(wallet));assert.equal(wallet.coins,coins-cost);assert.equal(arsenal.stats().damage,next.damage);
    assert.equal(arsenal.current.magazine,arsenal.stats().magazineSize);assert.equal(arsenal.current.reserve,arsenal.stats().maxReserve);
    lastGain=next.refinementBonus-previousBonus;if(level===1)firstGain=lastGain;
    previousBonus=next.refinementBonus;previousCost=cost;
  }
  assert.equal(arsenal.stats().tier,5);assert.equal(arsenal.forgeCost(),null);assert.ok(arsenal.refineCost()>previousCost);
  assert.ok(lastGain<firstGain/100);assert.ok(arsenal.stats().damage<initial*1.55,'500 upgrades improve power without exponential damage');
});
test('refinement is transactional, cancels pending reload and survives weapon rerolls',()=>{
  const arsenal=new Arsenal(),wallet=rich();for(let tier=0;tier<5;tier++)arsenal.forge(wallet);
  const roll=structuredClone(arsenal.current.roll),ammo=arsenal.current.magazine+arsenal.current.reserve;
  assert.equal(arsenal.refine({coins:1}),false);assert.deepEqual(arsenal.current.roll,roll);assert.equal(arsenal.current.magazine+arsenal.current.reserve,ammo);
  arsenal.current.magazine=1;arsenal.reload();assert.ok(arsenal.refine(wallet));assert.equal(arsenal.reloadState,null);arsenal.tick(10);
  assert.equal(arsenal.current.magazine,arsenal.stats().magazineSize);assert.equal(arsenal.current.reserve,arsenal.stats().maxReserve);
  assert.ok(arsenal.reroll('stat',wallet));assert.equal(arsenal.stats().refinement,1);
});
test('late drops keep their weapon level and offer bounded improvements over the same early roll',()=>{
  const early=rollWeapon({baseId:'horizon',rarity:'rare',round:1,seed:55}),late=rollWeapon({baseId:'horizon',rarity:'rare',round:100000,seed:55});
  const a=computeWeaponStats(early),b=computeWeaponStats(late);assert.equal(b.level,100000);assert.ok(b.damage>a.damage);assert.ok(b.damage<=a.damage*1.33);
  assert.equal(a.fireRate,b.fireRate);assert.equal(a.reloadTime,b.reloadTime);assert.ok(b.levelBonus<=.32);
});
test('shop discount previews and real charges agree for weapons, attachments, forge, refill and refinement',()=>{
  const arsenal=new Arsenal(),wallet=rich(),baseWeapon=arsenal.buyCost('hammer'),basePart=arsenal.attachmentCost('dot'),baseForge=arsenal.forgeCost();
  arsenal.setModifiers({shopDiscount:.8});assert.equal(arsenal.buyCost('hammer'),Math.round(baseWeapon*.8));assert.equal(arsenal.attachmentCost('dot'),Math.round(basePart*.8));
  assert.ok(Math.abs(arsenal.forgeCost()-baseForge*.8)<1);
  let coins=wallet.coins,cost=arsenal.buyCost('hammer');assert.ok(arsenal.buy('hammer',wallet,4));assert.equal(wallet.coins,coins-cost);
  coins=wallet.coins;cost=arsenal.attachmentCost('dot');assert.ok(arsenal.installAttachment('scope','dot',wallet));assert.equal(wallet.coins,coins-cost);
  arsenal.current.reserve=0;coins=wallet.coins;cost=arsenal.refillCost(20);assert.ok(arsenal.refill(wallet,20));assert.equal(wallet.coins,coins-cost);
  for(let tier=0;tier<5;tier++)arsenal.forge(wallet);coins=wallet.coins;cost=arsenal.refineCost();assert.ok(arsenal.refine(wallet));assert.equal(wallet.coins,coins-cost);
});
test('elemental and penetration perks affect real stats once, including alternating and fifth-arc shots',()=>{
  const arsenal=new Arsenal();arsenal.grant('ember');arsenal.equip('ember');arsenal.setModifiers({damage:2,elementalDamage:1.5,pierce:2});
  const config=arsenal.stats();assert.equal(config.damage,96);assert.equal(config.burnDamage,27);assert.equal(config.pierce,3);
  assert.equal(fireReady(arsenal).damage,96);
  const roll=withPerk('fifth_arc');roll.stock=true;roll.element='kinetic';roll.rolls={};const id=arsenal.addLoot(roll);arsenal.equip(id);
  const baseline=arsenal.stats().damage;assert.equal(arsenal.stats().appliedElementalDamage,1);
  for(let i=1;i<=5;i++){const shot=fireReady(arsenal);assert.equal(shot.damage,baseline*(i===5?1.5:1));}
  arsenal.current.roll.perk=null;arsenal.current.roll.attachments.magazine={id:'alternator',manufacturer:'remendo'};
  const fire=fireReady(arsenal);assert.equal(fire.damage,arsenal.stats().damage*1.5);assert.notEqual(fire.element,'kinetic');
});
test('spare attachments can be sold once and never produce profit through discounted purchases',()=>{
  const arsenal=new Arsenal(),wallet=rich();arsenal.setModifiers({shopDiscount:.25});
  for(const attachment of Object.values(ATTACHMENTS)){
    const id=arsenal.addAttachment(attachment.id),value=arsenal.salvageAttachmentValue(id),coins=wallet.coins;
    assert.ok(value<arsenal.attachmentCost(attachment.id));assert.equal(arsenal.salvageAttachment(id,wallet),value);
    assert.equal(wallet.coins,coins+value);assert.equal(arsenal.salvageAttachment(id,wallet),false);
  }
  assert.equal(arsenal.attachmentStash.size,0);
});
