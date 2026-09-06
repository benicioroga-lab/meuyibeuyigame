import {LOOT_WEAPONS,LOOT_WEAPON_BY_ID,RARITIES,MANUFACTURERS,ATTACHMENTS,ATTACHMENT_SLOTS,ELEMENTS,LEGENDARY_PERKS,FORGE_MAX_TIER,REFINEMENT_CONFIG,ITEM_LEVEL_CONFIG} from './loot-config.js';

export const clamp=(value,min,max)=>Math.max(min,Math.min(max,value));
const rounded=(value,places=2)=>Number(value.toFixed(places));
export function seedNumber(seed){
  if(typeof seed==='number'&&Number.isFinite(seed))return seed>>>0;
  let hash=2166136261;for(const character of String(seed??'')){hash^=character.charCodeAt(0);hash=Math.imul(hash,16777619);}return hash>>>0;
}
export function seededRandom(seed){let value=seedNumber(seed);return ()=>{value+=0x6D2B79F5;let out=value;out=Math.imul(out^(out>>>15),out|1);out^=out+Math.imul(out^(out>>>7),out|61);return ((out^(out>>>14))>>>0)/4294967296;};}
const pick=(items,random)=>items[Math.min(items.length-1,Math.floor(random()*items.length))];
const unlockWeighted=(items,unlocks,key,random)=>{
  const favorites=new Set(Array.isArray(unlocks)?unlocks:unlocks instanceof Set?[...unlocks]:[]);
  return pick([...items,...items.filter(item=>favorites.has(key?item[key]:item))],random);
};
export const normalizeElement=id=>({burn:'fire',chain:'shock',frost:'cryo'}[id]||id||'kinetic');
export function chooseRarity({round=1,difficulty='normal',chaos=0,random=Math.random,quality=0}={}){
  const challenge=typeof difficulty==='number'?difficulty:({easy:.65,normal:1,hard:1.25,insane:1.6,nightmare:1.9}[difficulty]||1);
  const bonus=clamp((round-1)*.006+(challenge-1)*.28+chaos*.1+quality,0,2.5);
  const entries=Object.values(RARITIES),weights=entries.map((entry,index)=>entry.weight*(index===0?1/(1+bonus):1+bonus*index*.8));
  let roll=random()*weights.reduce((sum,n)=>sum+n,0);
  for(let i=0;i<entries.length;i++){roll-=weights[i];if(roll<=0)return entries[i].id;}return 'mythic';
}

export function stockWeapon(baseId){
  const base=LOOT_WEAPON_BY_ID[baseId];if(!base)return null;
  return {uid:baseId,baseId,seed:0,level:1,rarity:'common',manufacturer:'remendo',stock:true,rolls:{},attachments:{},perk:null,element:normalizeElement(base.effect==='pierce'?'kinetic':base.effect),tier:0,refinement:0,rerolls:0,revision:0};
}

// A seed completely determines a roll. Challenge changes loot odds, never an unbounded stat multiplier.
export function rollWeapon({baseId,round=1,difficulty='normal',chaos=0,rarity,seed,random,metaUnlocks,quality=0}={}){
  round=Number.isFinite(round)?clamp(Math.floor(round),1,Number.MAX_SAFE_INTEGER):1;
  const actualSeed=seed??Math.floor((random||Math.random)()*4294967296),rng=seededRandom(actualSeed);
  const candidates=LOOT_WEAPONS.filter(weapon=>weapon.unlockRound<=Math.max(1,round));
  const base=LOOT_WEAPON_BY_ID[baseId]||unlockWeighted(candidates,metaUnlocks?.weaponIds,'id',rng),rarityId=RARITIES[rarity]?rarity:chooseRarity({round,difficulty,chaos,random:rng,quality});
  const rarityConfig=RARITIES[rarityId],manufacturer=unlockWeighted(Object.keys(MANUFACTURERS),metaUnlocks?.manufacturers,null,rng),rolls={};
  const availableStats=['damage','fireRate','magazineSize','reloadTime','criticalMultiplier','handling'];
  // Each advantage has a readable tradeoff. Affixes vary which stats receive the larger swing.
  for(let i=0;i<rarityConfig.affixes;i++){
    const key=availableStats.splice(Math.floor(rng()*availableStats.length),1)[0];
    rolls[key]=rounded(.88+rng()*.28,4);
  }
  const slots=[...ATTACHMENT_SLOTS],attachments={};
  const initialCount=Math.max(0,rarityConfig.slots-1);
  for(let i=0;i<initialCount;i++){
    const slot=slots.splice(Math.floor(rng()*slots.length),1)[0];
    const attachment=unlockWeighted(Object.values(ATTACHMENTS).filter(item=>item.slot===slot),metaUnlocks?.attachmentIds,'id',rng);
    attachments[slot]={id:attachment.id,manufacturer:pick(Object.keys(MANUFACTURERS),rng)};
  }
  const baseElement=normalizeElement(base.effect==='pierce'?'kinetic':base.effect);
  const elemental=baseElement!=='kinetic'||(rarityConfig.slots>=3&&rng()<.28+(MANUFACTURERS[manufacturer].elemental ? .15 : 0));
  const element=baseElement!=='kinetic'?baseElement:elemental?pick(['fire','shock','cryo','corrosive','explosive'],rng):'kinetic';
  const perk=rarityConfig.slots>=5?pick(Object.keys(LEGENDARY_PERKS),rng):null;
  return {uid:`${base.id}-${seedNumber(actualSeed).toString(36)}`,baseId:base.id,seed:seedNumber(actualSeed),level:round,rarity:rarityId,manufacturer,stock:false,rolls,attachments,perk,element,tier:0,refinement:0,rerolls:0,revision:0};
}

function multiply(stats,mods){for(const [key,value] of Object.entries(mods||{}))if(Number.isFinite(stats[key])&&Number.isFinite(value))stats[key]*=value;}
export function computeWeaponStats(roll,{upgrades={},modifiers={}}={}){
  if(!roll)return null;const base=LOOT_WEAPON_BY_ID[roll.baseId];if(!base)return null;
  const rarity=RARITIES[roll.rarity]||RARITIES.common,manufacturer=MANUFACTURERS[roll.manufacturer]||MANUFACTURERS.remendo;
  const result={...base,id:roll.uid,instanceId:roll.uid,weaponId:roll.uid,baseId:base.id,revision:roll.revision||0,rarity:rarity.id,rarityName:rarity.name,rarityLabel:rarity.label,rarityColor:rarity.color,raritySymbol:rarity.symbol,manufacturer:manufacturer.id,manufacturerName:manufacturer.name,attachments:structuredClone(roll.attachments||{}),attachmentSlots:rarity.slots,perk:roll.perk||null,perkName:LEGENDARY_PERKS[roll.perk]?.name||null,perkDescription:LEGENDARY_PERKS[roll.perk]?.description||null,tier:clamp(roll.tier||0,0,FORGE_MAX_TIER),level:roll.level||1,moveSpeed:1,burstCount:1,burstInterval:.075};
  let element=normalizeElement(roll.element||base.effect);if(element==='pierce')element='kinetic';
  if(!roll.stock){multiply(result,manufacturer.mods);result.criticalChance+=manufacturer.crit||0;result.damage*=rarity.power;}
  multiply(result,roll.rolls);
  for(const slot of ATTACHMENT_SLOTS){
    const installed=roll.attachments?.[slot];const attachment=ATTACHMENTS[typeof installed==='string'?installed:installed?.id];if(!attachment||attachment.slot!==slot)continue;
    multiply(result,attachment.mods);result.criticalChance+=attachment.crit||0;
    const piece=MANUFACTURERS[installed.manufacturer];
    // Manufacturer influence is small per part, independent of the weapon's core manufacturer.
    if(piece){const field={scope:'spread',barrel:'damage',magazine:'magazineSize',receiver:'fireRate',stock:'recoil',ammo:'damage'}[slot];const value=piece.mods?.[field];if(value)result[field]*=1+(value-1)*.4;}
    if(attachment.element)element=attachment.element;
    if(attachment.alternatingElements)result.alternatingElements=attachment.alternatingElements;
    if(attachment.burstCount){result.burstCount=attachment.burstCount;result.burstInterval=attachment.burstInterval;}
    if(attachment.pierce)result.pierce=Math.max(result.pierce||1,attachment.pierce);
    if(attachment.zoom)result.zoom=Math.max(result.zoom||1,attachment.zoom);
    if(attachment.moveSpeed)result.moveSpeed*=attachment.moveSpeed;
    if(attachment.silenced)result.silenced=true;
  }
  result.damage*=1+clamp(upgrades.damage||0,0,3)*.18+result.tier*.18;
  // Late finds improve in quality without forcing HP inflation. A cherished weapon can keep growing forever.
  result.level=Number.isFinite(result.level)?clamp(Math.floor(result.level),1,Number.MAX_SAFE_INTEGER):1;
  result.levelBonus=roll.stock?0:ITEM_LEVEL_CONFIG.maxDamageBonus*(1-Math.exp(-(result.level-1)/ITEM_LEVEL_CONFIG.roundScale));
  result.refinement=Number.isFinite(roll.refinement)?clamp(Math.floor(roll.refinement),0,Number.MAX_SAFE_INTEGER):0;
  result.refinementBonus=REFINEMENT_CONFIG.damageLogGrowth*Math.log2(1+result.refinement);
  result.damage*=1+result.levelBonus;
  result.damage*=1+result.refinementBonus;
  result.statusBaseMultiplier=(1+result.levelBonus)*(1+result.refinementBonus)*clamp(modifiers.damage??1,.1,8);
  result.magazineSize*=1+clamp(upgrades.magazine||0,0,2)*.25;
  result.reloadTime*=1-clamp(upgrades.reload||0,0,3)*.12;
  result.reloadTime*=1-result.tier*.025;
  result.criticalChance+=result.tier*.012;
  result.attachmentSlots=Math.min(6,result.attachmentSlots+Math.floor(result.tier/2));
  // Forge V unlocks a behavioral perk even on a common favorite.
  if(result.tier>=5&&!result.perk){result.perk='fifth_arc';result.perkName=LEGENDARY_PERKS.fifth_arc.name;result.perkDescription=LEGENDARY_PERKS.fifth_arc.description;}
  result.damage*=clamp(modifiers.damage??1,.1,8);result.fireRate*=clamp(modifiers.fireRate??1,.2,4);
  result.reloadTime*=clamp(modifiers.reloadTime??1,.2,3);result.moveSpeed*=clamp(modifiers.moveSpeed??1,.5,2);
  result.criticalChance+=clamp(modifiers.criticalChance||0,0,.7);result.criticalMultiplier*=clamp(modifiers.criticalMultiplier??1,1,4);
  result.maxReserve*=clamp(modifiers.reserveAmmo??1,1,4);
  if(roll.elementOverride)element=normalizeElement(roll.elementOverride);
  if(modifiers.element)element=normalizeElement(modifiers.element);
  const config=ELEMENTS[element]||ELEMENTS.kinetic;
  Object.assign(result,config,{id:roll.uid,element:config.id});
  if(element==='kinetic')result.color=base.color;
  // Retain the base weapon's special tuning unless a part actually changed its element.
  const baseElement=normalizeElement(base.effect);if(element===baseElement)for(const key of ['burnDamage','burnDuration','chainTargets','chainRadius','chainDamage','radius','splashDamage','slow','slowDuration'])if(base[key]!==undefined)result[key]=base[key];
  if(element==='kinetic'&&(result.pierce||0)>1)result.effect='pierce';
  result.pierce=Math.min(8,(result.pierce||1)+clamp(modifiers.pierce||0,0,7));
  if(element==='kinetic'&&result.pierce>1)result.effect='pierce';
  if(result.effect==='chain')result.chainTargets=Math.min(8,(result.chainTargets||2)+(modifiers.chainTargets||0));
  result.elementalDamageMultiplier=clamp(modifiers.elementalDamage??1,1,4);
  result.appliedElementalDamage=element==='kinetic'?1:result.elementalDamageMultiplier;
  result.damage*=result.appliedElementalDamage;
  for(const key of ['burnDamage','corrosionDamage'])if(result[key])result[key]*=result.statusBaseMultiplier*result.appliedElementalDamage;
  result.headshotExplosion=Math.max(modifiers.headshotExplosion||0,result.perk==='headburst'?1:0);
  result.damage=Math.max(1,result.refinement>0?rounded(result.damage,3):Math.round(result.damage));result.fireRate=rounded(clamp(result.fireRate,.35,32));
  result.magazineSize=Math.round(clamp(result.magazineSize,2,120));result.maxReserve=Math.round(clamp(result.maxReserve,result.magazineSize,1500));
  result.reloadTime=rounded(clamp(result.reloadTime,.35,5));result.emptyReloadTime=rounded(result.reloadTime*(base.family==='shotgun'?1.12:1.2));
  result.criticalChance=rounded(clamp(result.criticalChance,0,.8),3);result.criticalMultiplier=rounded(clamp(result.criticalMultiplier,1.2,5));
  result.recoil=clamp(result.recoil,.001,.075);result.spread=clamp(result.spread,0,.13);result.aimSpread=clamp(result.aimSpread,0,.065);
  result.range=rounded(clamp(result.range,12,180));result.handling=Math.round(clamp(result.handling,25,100));
  result.equipTime=rounded(clamp(.32-(result.handling-65)*.003,.15,.46));result.accuracy=Math.round(clamp(100-result.spread*900,0,100));
  result.price=base.price;result.name=base.name; // Element names describe the ammunition, not the weapon.
  return result;
}

export function compareWeapons(before,after){
  return [['damage','Dano','',1],['fireRate','Cadência','/s',1],['magazineSize','Pente','',1],['reloadTime','Recarga','s',-1],['criticalChance','Crítico','%',1],['criticalMultiplier','Dano crítico','×',1],['handling','Controle','',1]].map(([key,label,unit,direction])=>{
    const scale=key==='criticalChance'?100:1,a=rounded((before?.[key]||0)*scale),b=rounded((after?.[key]||0)*scale),delta=rounded(b-a);
    return {key,label,before:a,after:b,delta,better:delta===0?null:delta*direction>0,unit};
  });
}
