import test from 'node:test';
import assert from 'node:assert/strict';
import {difficultyPreview,formatPerkDelta} from '../systems/run-ui.js';
import {DIFFICULTIES,CHAOS_LEVELS,PERKS} from '../systems/run-config.js';

test('menu rewards and enemy health match the exact difficulty and Chaos multipliers',()=>{
  for(const difficulty of DIFFICULTIES)for(const chaos of CHAOS_LEVELS){const shown=difficultyPreview(difficulty.id,chaos.level);assert.equal(shown.reward,difficulty.reward*chaos.reward);assert.equal(shown.loot,difficulty.lootChance*chaos.lootChance);assert.equal(shown.health,difficulty.health*chaos.health);assert.equal(shown.damage,difficulty.damage*chaos.damage);}
  assert.equal(difficultyPreview('invalid',-1).difficulty.id,'normal');assert.equal(difficultyPreview('invalid',-1).chaos.level,0);
});
test('build choices explain the actual next change instead of only showing a level name',()=>{
  assert.deepEqual(formatPerkDelta({...PERKS.recycle,level:1}),{before:'5% do pente por kill',after:'10% do pente por kill'});
  assert.deepEqual(formatPerkDelta({...PERKS.riskTaker,level:0}),{before:'+0% dano · −0% vida',after:'+12% dano · −8% vida'});
  assert.deepEqual(formatPerkDelta({...PERKS.bond,level:2}),{before:'+30% dano Faro · −14% intervalo',after:'+45% dano Faro · −21% intervalo'});
  assert.equal(formatPerkDelta(PERKS.supply).after,PERKS.supply.description);
});
