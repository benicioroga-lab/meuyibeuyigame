import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createShop,comparisonHTML} from '../systems/shop.js';
import {Arsenal} from '../systems/arsenal.js';
import {rollWeapon} from '../systems/weapon-rolls.js';
import {DogTraining} from '../systems/dog.js';
import {RunDirector} from '../systems/run-director.js';

function fixture(){
  const listeners={},root={innerHTML:'',parentElement:{scrollTop:0},classList:{add(){}},addEventListener:(name,fn)=>listeners[name]=fn,removeEventListener:name=>delete listeners[name],contains:()=>true,querySelectorAll:()=>[]},coins={textContent:''};
  const prior=globalThis.document;globalThis.document={getElementById:id=>id==='upgradeList'?root:id==='drawerCoins'?coins:null};
  const arsenal=new Arsenal(),state={coins:100000,upgrades:{}},training=new DogTraining(),director=new RunDirector(),toasts=[];
  const shop=createShop({state,roundState:{round:20},combat:{arsenal},dog:{training},getDirector:()=>director,toast:text=>toasts.push(text)});
  const click=(action,id='')=>listeners.click({target:{closest:()=>({dataset:{action,id},disabled:false})}});
  const change=(control,value)=>listeners.change({target:{dataset:{control},value}});
  return {shop,arsenal,root,state,click,change,toasts,restore(){shop.dispose();globalThis.document=prior;}};
}

test('comparison shows real crit percentages and understands that shorter reload is better',()=>{
  const before={damage:22,fireRate:3.2,magazineSize:12,reloadTime:2,criticalChance:.05,criticalMultiplier:1.65,handling:60},after={...before,criticalChance:.12,reloadTime:1.5};
  const html=comparisonHTML(before,after);assert.match(html,/>5%<\/b>/);assert.match(html,/>12%<\/strong>/);assert.doesNotMatch(html,/500%|1200%/);
  assert.match(html,/class="comparison-row better"><span>Recarga<\/span><b>2s<\/b>/);assert.match(html,/192 RPM/);
});
test('shotgun card reports total trigger damage once and keeps comparison on the same unit',()=>{
  const {shop,arsenal,root,restore}=fixture();try{
    shop.openTab('weapons');const cascade=root.innerHTML.split('<h3>Cascata</h3>')[1].split('</article>')[0];
    assert.match(cascade,/DANO \/ DISPARO<b>96<small class="pellet-caption">TOTAL · 8 PROJÉTEIS/);assert.doesNotMatch(cascade,/96 × 8/);
    assert.match(cascade,/<strong>96<\/strong>/);assert.equal(arsenal.stats('cascade').damage,96);
  }finally{restore();}
});
test('rolled carbine retains its real manufacturer, element and damage in inventory detail',()=>{
  const {shop,arsenal,root,click,restore}=fixture();try{
    const roll=rollWeapon({baseId:'boardwalk',rarity:'rare',seed:980});roll.manufacturer='agulha';roll.element='shock';roll.attachments={};const id=arsenal.addLoot(roll),stats=arsenal.stats(id);
    shop.openTab('inventory');click('inspect',id);assert.match(root.innerHTML,/<h3>Calçadão<\/h3>/);assert.match(root.innerHTML,/Agulha Óptica · Choque/);
    assert.ok(root.innerHTML.includes(`DANO / DISPARO<b>${stats.damage}`));assert.equal(stats.effect,'chain');
  }finally{restore();}
});
test('base catalog recognizes the equipped roll when the player owns two variants of one gun',()=>{
  const {shop,arsenal,root,restore}=fixture();try{
    arsenal.addLoot(rollWeapon({baseId:'boardwalk',rarity:'uncommon',seed:501}));const second=rollWeapon({baseId:'boardwalk',rarity:'rare',seed:502});second.manufacturer='prisma';second.element='cryo';second.attachments={};const id=arsenal.addLoot(second);arsenal.equip(id);
    shop.openTab('weapons');const card=root.innerHTML.split('<div class="weapon-catalog">')[1].split('<h3>Calçadão</h3>')[1].split('</article>')[0];assert.match(card,/Prisma Circuitos · Gelo/);assert.match(card,/EQUIPADA/);assert.ok(card.includes(`data-id="${id}"`));
  }finally{restore();}
});
test('all shop categories render from current Arsenal and DogTraining contracts',()=>{
  const {shop,root,restore}=fixture();try{
    for(const tab of['weapons','inventory','attachments','dog','player','forge']){assert.equal(shop.openTab(tab),true);assert.ok(root.innerHTML.length>400,tab);}
    shop.openTab('dog');assert.match(root.innerHTML,/Suporte/);assert.match(root.innerHTML,/Sobrevivência/);assert.match(root.innerHTML,/30 %/);assert.doesNotMatch(root.innerHTML,/>0.3 %/);
    shop.openTab('attachments');assert.match(root.innerHTML,/Fabricante da peça/);assert.match(root.innerHTML,/Ponto âmbar/);
    shop.openTab('player');assert.match(root.innerHTML,/Mãos ligeiras/);
  }finally{restore();}
});
test('favorites toggle in both directions and protected items cannot be salvaged through UI',()=>{
  const {shop,arsenal,root,state,click,restore}=fixture();try{
    const id=arsenal.addLoot(rollWeapon({seed:44,rarity:'rare'}));shop.openTab('inventory');click('inspect',id);click('favorite',id);
    assert.equal(arsenal.inventory.get(id).favorite,true);assert.match(root.innerHTML,/★ FAVORITA/);const before=state.coins;click('salvage',id);assert.equal(state.coins,before);assert.equal(arsenal.inventory.has(id),true);
    click('favorite',id);assert.equal(arsenal.inventory.get(id).favorite,false);assert.match(root.innerHTML,/☆ MARCAR FAVORITA/);click('salvage',id);assert.ok(state.coins>before);assert.equal(arsenal.inventory.has(id),false);
  }finally{restore();}
});
test('forging and rerolls only spend currency after interacting with a forge station',()=>{
  const {shop,arsenal,state,root,click,restore}=fixture();try{
    shop.openTab('forge');assert.match(root.innerHTML,/Encontre a estação/);const before=state.coins;click('forge');click('reroll','stat');assert.equal(state.coins,before);assert.equal(arsenal.current.roll.tier,0);
    shop.setStation('forge');shop.render();assert.match(root.innerHTML,/FORJA ATIVA/);const cost=arsenal.forgeCost();click('forge');assert.equal(arsenal.current.roll.tier,1);assert.equal(state.coins,before-cost);
    shop.setStation(null);click('forge');assert.equal(arsenal.current.roll.tier,1);
  }finally{restore();}
});
test('attachment controls preview exact manufacturer parts and installing consumes the displayed cost',()=>{
  const {shop,arsenal,state,root,click,change,restore}=fixture();try{
    shop.openTab('attachments');change('slot','magazine');change('manufacturer','muralha');const before=arsenal.stats().magazineSize,coins=state.coins,cost=arsenal.attachmentCost('extended');assert.match(root.innerHTML,/Pente alongado/);
    click('attachment','extended');assert.ok(arsenal.stats().magazineSize>before);assert.equal(state.coins,coins-cost);assert.equal(arsenal.current.roll.attachments.magazine.manufacturer,'muralha');assert.match(root.innerHTML,/JÁ INSTALADA/);
  }finally{restore();}
});
test('attachment cards reveal recoil, accuracy and range changes that damage-only tables miss',()=>{
  const {shop,root,change,restore}=fixture();try{
    shop.openTab('attachments');change('slot','barrel');const card=root.innerHTML.split('<h3>Freio de recuo</h3>')[1].split('</article>')[0];
    assert.match(card,/EFEITO DA PEÇA/);assert.match(card,/>Recuo<\/span>/);assert.match(card,/>0.516°<\/b>/);assert.match(card,/>0.345°<\/strong>/);assert.match(card,/>Alcance<\/span><b>75 m<\/b>/);assert.match(card,/>69 m<\/strong>/);
  }finally{restore();}
});
test('forged common weapons expose the unlocked behavioral perk reroll',()=>{
  const {shop,arsenal,root,state,restore}=fixture();try{
    for(let i=0;i<5;i++)assert.equal(arsenal.forge(state),true);shop.setStation('forge');shop.openTab('forge');
    assert.match(root.innerHTML,/Reroll · Traço lendário/);assert.match(root.innerHTML,/data-action="reroll" data-id="perk"\s*>REFORJAR/);
  }finally{restore();}
});
test('refinement stays available after Forge V, shows next power and charges the exact escalating cost',()=>{
  const {shop,arsenal,root,state,click,restore}=fixture();try{
    for(let i=0;i<5;i++)assert.equal(arsenal.forge(state),true);shop.setStation('forge');shop.openTab('forge');assert.match(root.innerHTML,/APERFEIÇOAMENTO CONTÍNUO/);
    for(let i=0;i<3;i++){
      const coins=state.coins,cost=arsenal.refineCost(),damage=arsenal.stats().damage;arsenal.current.magazine=0;arsenal.current.reserve=0;
      click('refine');assert.equal(arsenal.current.roll.refinement,i+1);assert.equal(state.coins,coins-cost);assert.ok(arsenal.stats().damage>damage);assert.equal(arsenal.current.magazine,arsenal.stats().magazineSize);assert.ok(arsenal.refineCost()>cost);
    }
    assert.match(root.innerHTML,/NÍVEL 3/);shop.setStation(null);const before=state.coins;click('refine');assert.equal(state.coins,before);
  }finally{restore();}
});
test('limited dealer discounts change both displayed and charged attachment prices',()=>{
  const {shop,arsenal,state,root,click,restore}=fixture();try{
    arsenal.setModifiers({shopDiscount:.8});shop.openTab('attachments');const price=arsenal.attachmentCost('dot'),coins=state.coins;assert.equal(price,72);assert.match(root.innerHTML,/◈ 72/);
    click('attachment','dot');assert.equal(state.coins,coins-price);
  }finally{restore();}
});
test('removing and recycling parts frees a common weapon slot and bag capacity without duplicate money',()=>{
  const {shop,arsenal,state,root,click,restore}=fixture();try{
    arsenal.installAttachment('scope','dot',state,'agulha');shop.openTab('attachments');assert.match(root.innerHTML,/RETIRAR PARA A BOLSA/);
    click('remove-part','scope');assert.equal(arsenal.current.roll.attachments.scope,undefined);assert.equal(arsenal.attachmentStash.size,1);assert.ok(arsenal.previewAttachment('ammo','shockcell'));
    const part=[...arsenal.attachmentStash.keys()][0],coins=state.coins,value=arsenal.salvageAttachmentValue(part);assert.match(root.innerHTML,/data-action="salvage-part"/);
    click('salvage-part',part);assert.equal(state.coins,coins+value);assert.equal(arsenal.attachmentStash.size,0);click('salvage-part',part);assert.equal(state.coins,coins+value);
  }finally{restore();}
});
