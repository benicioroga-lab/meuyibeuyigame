import {WEAPONS,WEAPON_UPGRADES,ECONOMY} from './config.js';
import {LOOT_WEAPON_BY_ID,RARITIES,MANUFACTURERS,ATTACHMENTS,ATTACHMENT_SLOTS,ELEMENTS,LEGENDARY_PERKS,FORGE_MAX_TIER,INVENTORY_LIMIT,REFINEMENT_CONFIG} from './loot-config.js';
import {stockWeapon,rollWeapon,computeWeaponStats,compareWeapons,normalizeElement,clamp} from './weapon-rolls.js';

// Simulation only: one shared firing clock, explicit ammunition transfers, no wall-clock timers.
export class Arsenal {
  constructor({emit=()=>{},random=Math.random,getModifiers=null}={}) {
    this.emit=emit;this.random=random;this.getModifiers=getModifiers;this.modifiers={};
    this.inventory=new Map();this.attachmentStash=new Map();this.currentId=WEAPONS[0].id;
    this.cooldown=0;this.reloadState=null;this.animationState=null;this.emptyCooldown=0;this.bloom=0;
    this.burstRemaining=0;this.burstWeaponId=null;this.burstRecovery=0;this.serial=0;this.inspectCount=0;this.capacityModifier=1;
    this.grant(this.currentId);
  }
  get current(){return this.inventory.get(this.currentId);}
  activeModifiers(){return this.getModifiers?.()||this.modifiers;}
  setModifiers(modifiers={}){this.modifiers={...modifiers};return this;}
  shopPrice(base){return Math.round(base*clamp(this.activeModifiers().shopDiscount??1,.25,1));}
  buyCost(id){const config=LOOT_WEAPON_BY_ID[id];return config?this.shopPrice(config.price):null;}
  createEntry(roll){
    const config=computeWeaponStats(roll);return {id:roll.uid,baseId:roll.baseId,roll,magazine:config.magazineSize,reserve:Math.min(config.maxReserve,config.reserveAmmo),upgrades:{damage:0,magazine:0,reload:0},favorite:false,shots:0,tempoStacks:0,tempoTime:0};
  }
  grant(id){
    const roll=stockWeapon(id);if(!roll||this.inventory.has(id)||this.inventory.size>=INVENTORY_LIMIT)return false;
    this.inventory.set(id,this.createEntry(roll));return true;
  }
  addLoot(roll){
    if(!roll||!LOOT_WEAPON_BY_ID[roll.baseId]||!RARITIES[roll.rarity]||this.inventory.size>=INVENTORY_LIMIT)return false;
    const copy=structuredClone(roll);copy.uid=String(copy.uid||`${copy.baseId}-drop`);
    if(this.inventory.has(copy.uid)){const stem=copy.uid;do{copy.uid=`${stem}-${++this.serial}`;}while(this.inventory.has(copy.uid));}
    this.inventory.set(copy.uid,this.createEntry(copy));this.emit({type:'loot-added',id:copy.uid,rarity:copy.rarity});return copy.uid;
  }
  grantRoll(roll){return this.addLoot(roll);}
  stats(id=this.currentId){
    const entry=this.inventory.get(id),roll=entry?.roll||stockWeapon(id);if(!roll)return null;
    const config=computeWeaponStats(roll,{upgrades:entry?.upgrades,modifiers:this.activeModifiers()});
    if(entry?.tempoTime>0)config.fireRate=Number(Math.min(32,config.fireRate*(1+entry.tempoStacks*.08)).toFixed(2));
    return config;
  }
  buy(id,wallet,round){
    const config=LOOT_WEAPON_BY_ID[id],cost=this.buyCost(id);if(!config||this.inventory.has(id)||this.inventory.size>=INVENTORY_LIMIT||round<config.unlockRound||!canPay(wallet,cost))return false;
    wallet.coins-=cost;this.grant(id);this.equip(id);this.emit({type:'purchase',id,cost});return true;
  }
  equip(id){
    if(id===this.currentId||!this.inventory.has(id))return false;
    const previous=this.currentId;this.cancelReload();this.cancelBurst();this.currentId=id;this.bloom=0;
    const duration=this.stats().equipTime;this.animationState={type:'equip',fromId:previous,id,remaining:duration,total:duration};
    // Switching preserves the previous gun's fire clock. Holstering cannot multiply heavy-weapon DPS.
    this.cooldown=Math.max(this.cooldown,duration);this.emit({type:'equip',id,previous,duration});return true;
  }
  cycle(direction){const ids=[...this.inventory.keys()],index=ids.indexOf(this.currentId),step=direction<0?-1:1;return this.equip(ids[(index+step+ids.length)%ids.length]);}
  inspect(){
    if(this.reloadState||this.burstRemaining)return false;
    this.animationState={type:'inspect',remaining:1.5,total:1.5};this.inspectCount++;this.emit({type:'inspect',id:this.currentId});return true;
  }
  reload(){
    const entry=this.current,config=this.stats();if(this.reloadState||entry.magazine>=config.magazineSize||entry.reserve<=0)return false;
    this.cancelBurst();this.animationState=null;const kind=entry.magazine===0?'empty':'tactical',duration=kind==='empty'?config.emptyReloadTime:config.reloadTime;
    this.reloadState={id:entry.id,kind,remaining:duration,total:duration,magazineBefore:entry.magazine};
    this.emit({type:'reload-start',id:entry.id,kind,duration});return true;
  }
  cancelReload(){if(!this.reloadState)return false;this.reloadState=null;this.emit({type:'reload-cancel'});return true;}
  cancelBurst(){if(this.burstRemaining)this.cooldown=Math.max(this.cooldown,this.burstRecovery);this.burstRemaining=0;this.burstWeaponId=null;}
  reconcileAmmo(entry){
    const stats=this.stats(entry.id),excess=Math.max(0,entry.magazine-stats.magazineSize);entry.magazine-=excess;
    const before=entry.reserve+excess;entry.reserve=Math.max(0,Math.min(stats.maxReserve,before));
    if(before>entry.reserve)this.emit({type:'ammo-discard',id:entry.id,amount:before-entry.reserve});
  }
  tick(dt){
    if(!Number.isFinite(dt)||dt<0)return;
    const capacityModifier=this.activeModifiers().reserveAmmo??1;
    if(capacityModifier!==this.capacityModifier){this.capacityModifier=capacityModifier;for(const entry of this.inventory.values())this.reconcileAmmo(entry);}
    this.cooldown=Math.max(0,this.cooldown-dt);this.emptyCooldown=Math.max(0,this.emptyCooldown-dt);this.bloom=Math.max(0,this.bloom-dt*3.5);
    this.burstRecovery=Math.max(0,this.burstRecovery-dt);
    if(this.animationState){this.animationState.remaining-=dt;if(this.animationState.remaining<=0)this.animationState=null;}
    for(const entry of this.inventory.values())if(entry.tempoTime>0){entry.tempoTime=Math.max(0,entry.tempoTime-dt);if(entry.tempoTime===0)entry.tempoStacks=0;}
    if(this.reloadState){
      this.reloadState.remaining-=dt;
      if(this.reloadState.remaining<=0){
        const pending=this.reloadState,entry=this.inventory.get(pending.id);this.reloadState=null;
        if(entry&&entry.id===this.currentId){const capacity=this.stats().magazineSize,transfer=Math.max(0,Math.min(capacity-entry.magazine,entry.reserve));entry.magazine+=transfer;entry.reserve-=transfer;this.emit({type:'reload-end',id:entry.id,kind:pending.kind,transfer});}
      }
    }
  }
  fire({aiming=false,burstFollowup=false}={}){
    if(this.reloadState||this.cooldown>1e-7)return null;
    if(burstFollowup&&(!this.burstRemaining||this.burstWeaponId!==this.currentId))return null;
    if(!burstFollowup&&this.burstRemaining)return null;
    const entry=this.current,config=this.stats(),mods=this.activeModifiers(),infiniteAmmo=Boolean(mods.infiniteAmmo);
    if(entry.magazine<=0&&!infiniteAmmo){this.cancelBurst();if(this.emptyCooldown<=0){this.emit({type:'empty'});this.emptyCooldown=.45;}this.reload();return null;}
    if(this.animationState?.type==='inspect')this.animationState=null;
    const magazineBefore=entry.magazine;if(!infiniteAmmo)entry.magazine--;entry.shots++;
    if(burstFollowup)this.burstRemaining--;
    else if(config.burstCount>1){this.burstRemaining=Math.min(config.burstCount-1,infiniteAmmo?config.burstCount-1:entry.magazine);this.burstWeaponId=entry.id;this.burstRecovery=config.burstCount/config.fireRate;}
    this.cooldown=this.burstRemaining>0?config.burstInterval:Math.max(1/config.fireRate,this.burstRecovery);this.bloom=Math.min(1,this.bloom+.14);
    let element=config.element;if(config.alternatingElements&&!mods.element)element=config.alternatingElements[(entry.shots-1)%config.alternatingElements.length];
    const empowered=config.perk==='fifth_arc'&&entry.shots%5===0;if(empowered)element='shock';
    const shot={...config,shotIndex:entry.shots,magazineBefore,magazineAfter:entry.magazine,weaponId:entry.id,burstFollowup,critical:this.random()<config.criticalChance,spread:aiming?config.aimSpread:config.spread*(1+this.bloom*.4),bonusShots:config.perk==='echo'&&this.random()<.1?1:0};
    if(element!==config.element){
      Object.assign(shot,ELEMENTS[element]||ELEMENTS.kinetic,{id:entry.id,name:config.name,element});
      const elementalMultiplier=element==='kinetic'?1:config.elementalDamageMultiplier;
      shot.damage*=elementalMultiplier/config.appliedElementalDamage;
      for(const key of ['burnDamage','corrosionDamage'])if(shot[key])shot[key]*=config.statusBaseMultiplier*elementalMultiplier;
      shot.appliedElementalDamage=elementalMultiplier;
      if(element==='shock')shot.chainTargets=Math.min(8,(shot.chainTargets||2)+(mods.chainTargets||0));
    }
    if(config.perk==='last_word'&&magazineBefore===1){shot.damage*=4;shot.lastBullet=true;}
    if(empowered)Object.assign(shot,{effect:'chain',element:'shock',chainTargets:Math.min(8,4+(mods.chainTargets||0)),chainRadius:6,chainDamage:.55,color:'#a6e5f6',empowered:true});
    this.emit({type:'shot',shot});return shot;
  }
  onKill({weaponId=this.currentId,headshot=false}={}){
    const entry=this.inventory.get(weaponId);if(!entry)return;
    const config=this.stats(weaponId),mods=this.activeModifiers();
    if(config.perk==='tempo'){entry.tempoStacks=Math.min(5,entry.tempoStacks+1);entry.tempoTime=5;}
    const fraction=clamp(mods.killReload||0,0,.5);
    if(fraction>0){const transfer=Math.min(config.magazineSize-entry.magazine,entry.reserve,Math.ceil(config.magazineSize*fraction));entry.magazine+=transfer;entry.reserve-=transfer;if(transfer>0)this.emit({type:'kill-reload',id:entry.id,transfer});}
  }
  addAmmo(fraction=ECONOMY.ammoPickupFraction){
    if(!Number.isFinite(fraction)||fraction<=0)return 0;let added=0;
    for(const entry of this.inventory.values()){const config=this.stats(entry.id),amount=Math.max(0,Math.min(config.maxReserve-entry.reserve,Math.ceil(config.magazineSize*fraction)));entry.reserve+=amount;added+=amount;}return added;
  }
  refillCost(round){return this.shopPrice(ECONOMY.ammoShopBase+Math.max(1,round)*ECONOMY.ammoShopRoundScale);}
  refill(wallet,round){const cost=this.refillCost(round),entry=this.current,config=this.stats();if(!canPay(wallet,cost)||entry.reserve>=config.maxReserve)return false;wallet.coins-=cost;entry.reserve=config.maxReserve;this.emit({type:'refill',cost});return true;}
  upgradeCost(kind,id=this.currentId){const config=WEAPON_UPGRADES[kind],entry=this.inventory.get(id);if(!config||!entry||entry.upgrades[kind]>=config.max)return null;return this.shopPrice(config.baseCost*Math.pow(config.costScale,entry.upgrades[kind])*(1+LOOT_WEAPON_BY_ID[entry.baseId].unlockRound*.08));}
  upgrade(kind,wallet){const cost=this.upgradeCost(kind);if(cost===null||!canPay(wallet,cost))return false;wallet.coins-=cost;this.current.upgrades[kind]++;this.current.roll.revision++;this.emit({type:'weapon-upgrade',kind,cost});return true;}
  nextStats(kind){if(this.upgradeCost(kind)===null)return null;const levels={...this.current.upgrades,[kind]:this.current.upgrades[kind]+1};return computeWeaponStats(this.current.roll,{upgrades:levels,modifiers:this.activeModifiers()});}
  forgeCost(id=this.currentId){const entry=this.inventory.get(id);if(!entry||entry.roll.tier>=FORGE_MAX_TIER)return null;return this.shopPrice(220*Math.pow(1.85,entry.roll.tier)*(1+LOOT_WEAPON_BY_ID[entry.baseId].unlockRound*.07));}
  previewForge(){if(this.forgeCost()===null)return null;return computeWeaponStats({...this.current.roll,tier:this.current.roll.tier+1},{upgrades:this.current.upgrades,modifiers:this.activeModifiers()});}
  nextForgeStats(){return this.previewForge();}
  forge(wallet){const cost=this.forgeCost();if(cost===null||!canPay(wallet,cost))return false;wallet.coins-=cost;this.current.roll.tier++;this.current.roll.revision++;this.emit({type:'forge',cost,id:this.currentId,tier:this.current.roll.tier});return true;}
  refineCost(id=this.currentId){
    const entry=this.inventory.get(id);if(!entry||entry.roll.tier<FORGE_MAX_TIER)return null;
    const level=this.stats(id).refinement,{baseCost,levelCost,growthCost,costExponent}=REFINEMENT_CONFIG;
    return this.shopPrice((baseCost+level*levelCost+growthCost*Math.pow(level,costExponent))*(1+LOOT_WEAPON_BY_ID[entry.baseId].unlockRound*.06));
  }
  previewRefine(){if(this.refineCost()===null)return null;return computeWeaponStats({...this.current.roll,refinement:this.stats().refinement+1},{upgrades:this.current.upgrades,modifiers:this.activeModifiers()});}
  refine(wallet){
    const cost=this.refineCost();if(cost===null||!canPay(wallet,cost))return false;
    wallet.coins-=cost;this.current.roll.refinement=this.stats().refinement+1;this.current.roll.revision++;
    this.cancelReload();this.cancelBurst();const config=this.stats();this.current.magazine=config.magazineSize;this.current.reserve=config.maxReserve;
    this.emit({type:'refine',id:this.currentId,cost,refinement:config.refinement});return true;
  }
  rerollCost(kind,id=this.currentId){const entry=this.inventory.get(id);if(!entry||!['stat','attachment','element','perk'].includes(kind)||kind==='perk'&&RARITIES[entry.roll.rarity].slots<5&&entry.roll.tier<5)return null;const base={stat:120,attachment:160,element:200,perk:360}[kind];return this.shopPrice(base*Math.pow(1.4,Math.min(15,entry.roll.rerolls||0)));}
  reroll(kind,wallet){
    const cost=this.rerollCost(kind);if(cost===null||!canPay(wallet,cost))return false;
    const roll=this.current.roll,next=rollWeapon({baseId:roll.baseId,round:roll.level,rarity:roll.rarity,seed:Math.floor(this.random()*4294967296)});
    if(kind==='stat'){
      const keys=['damage','fireRate','magazineSize','reloadTime','criticalMultiplier','handling'],key=keys[Math.min(keys.length-1,Math.floor(this.random()*keys.length))];roll.rolls[key]=Number((.88+this.random()*.28).toFixed(4));
    }
    if(kind==='element'){const current=this.stats().element,ids=Object.keys(ELEMENTS).filter(id=>id!==current);roll.element=ids[Math.min(ids.length-1,Math.floor(this.random()*ids.length))];roll.elementOverride=roll.element;}
    if(kind==='perk'){const ids=Object.keys(LEGENDARY_PERKS).filter(id=>id!==roll.perk);roll.perk=ids[Math.min(ids.length-1,Math.floor(this.random()*ids.length))];}
    if(kind==='attachment'){
      const occupied=Object.keys(roll.attachments),slot=occupied.length?occupied[Math.min(occupied.length-1,Math.floor(this.random()*occupied.length))]:ATTACHMENT_SLOTS[Math.min(5,Math.floor(this.random()*6))];
      const options=Object.values(ATTACHMENTS).filter(item=>item.slot===slot&&item.id!==roll.attachments[slot]?.id),attachment=options[Math.min(options.length-1,Math.floor(this.random()*options.length))];
      roll.attachments[slot]={id:attachment.id,manufacturer:next.manufacturer};
    }
    wallet.coins-=cost;roll.rerolls=(roll.rerolls||0)+1;roll.revision++;this.cancelReload();this.cancelBurst();this.reconcileAmmo(this.current);this.emit({type:'reroll',kind,cost,id:this.currentId});return true;
  }
  attachmentCost(id){return ATTACHMENTS[id]?this.shopPrice(ATTACHMENTS[id].price):null;}
  attachmentAllowed(slot,id){return ATTACHMENTS[id]?.slot===slot&&(Boolean(this.current.roll.attachments[slot])||Object.keys(this.current.roll.attachments).length<this.stats().attachmentSlots);}
  addAttachment(id,manufacturer='remendo'){
    if(!ATTACHMENTS[id]||this.attachmentStash.size>=40)return false;const key=`part-${++this.serial}`;
    this.attachmentStash.set(key,{id:key,attachmentId:id,manufacturer:MANUFACTURERS[manufacturer]?manufacturer:'remendo'});this.emit({type:'attachment-found',id:key,attachmentId:id});return key;
  }
  previewAttachment(slot,id,manufacturer='remendo'){
    if(!this.attachmentAllowed(slot,id))return null;
    return computeWeaponStats({...this.current.roll,attachments:{...this.current.roll.attachments,[slot]:{id,manufacturer}}},{upgrades:this.current.upgrades,modifiers:this.activeModifiers()});
  }
  installAttachment(slot,id,wallet,manufacturer='remendo',stashId=null){
    if(!this.attachmentAllowed(slot,id))return false;
    const cost=wallet?this.attachmentCost(id):0;
    let owned;if(!wallet){owned=stashId?this.attachmentStash.get(stashId):[...this.attachmentStash.values()].find(part=>part.attachmentId===id);if(!owned||owned.attachmentId!==id)return false;manufacturer=owned.manufacturer;}
    else if(!canPay(wallet,cost))return false;
    const previous=this.current.roll.attachments[slot];if(previous&&this.attachmentStash.size>=40&&!owned)return false;
    if(wallet)wallet.coins-=cost;else this.attachmentStash.delete(owned.id);
    if(previous)this.addAttachment(previous.id,previous.manufacturer);
    this.current.roll.attachments[slot]={id,manufacturer:MANUFACTURERS[manufacturer]?manufacturer:'remendo'};this.current.roll.revision++;
    if(ATTACHMENTS[id].element||ATTACHMENTS[id].alternatingElements)delete this.current.roll.elementOverride;
    this.cancelReload();this.cancelBurst();this.reconcileAmmo(this.current);this.emit({type:'attachment',id,slot,cost});return true;
  }
  equipAttachment(stashId){const part=this.attachmentStash.get(stashId);return part?this.installAttachment(ATTACHMENTS[part.attachmentId].slot,part.attachmentId,undefined,part.manufacturer,stashId):false;}
  salvageAttachmentValue(stashId){const part=this.attachmentStash.get(stashId);return part?Math.floor(ATTACHMENTS[part.attachmentId].price*.18):0;}
  salvageAttachment(stashId,wallet){
    const value=this.salvageAttachmentValue(stashId);if(value<=0||!wallet||!Number.isFinite(wallet.coins))return false;
    this.attachmentStash.delete(stashId);wallet.coins+=value;this.emit({type:'attachment-salvage',id:stashId,value});return value;
  }
  removeAttachment(slot){
    const part=this.current.roll.attachments[slot];if(!part||this.attachmentStash.size>=40)return false;
    this.addAttachment(part.id,part.manufacturer);delete this.current.roll.attachments[slot];this.current.roll.revision++;this.cancelReload();this.cancelBurst();this.reconcileAmmo(this.current);this.emit({type:'attachment',slot,cost:0});return true;
  }
  toggleFavorite(uid=this.currentId){const entry=this.inventory.get(uid);if(!entry)return false;entry.favorite=!entry.favorite;this.emit({type:'favorite',id:uid,favorite:entry.favorite});return entry.favorite;}
  salvageValue(uid){const entry=this.inventory.get(uid);if(!entry||entry.roll.stock&&LOOT_WEAPON_BY_ID[entry.baseId].price===0)return 0;return Math.round(RARITIES[entry.roll.rarity].scrap*(1+entry.roll.tier*.35)+LOOT_WEAPON_BY_ID[entry.baseId].price*.08);}
  salvage(uid,wallet){
    const entry=this.inventory.get(uid);if(!entry||entry.favorite||this.inventory.size<=1||!wallet||!Number.isFinite(wallet.coins))return false;
    const value=this.salvageValue(uid);if(value<=0)return false;
    if(uid===this.currentId)this.equip([...this.inventory.keys()].find(id=>id!==uid));
    this.inventory.delete(uid);wallet.coins+=value;this.emit({type:'salvage',id:uid,value});return value;
  }
  compare(rollOrUid){const target=typeof rollOrUid==='string'?this.stats(rollOrUid):computeWeaponStats(rollOrUid,{modifiers:this.activeModifiers()});return target?compareWeapons(this.stats(),target):[];}
}
function canPay(wallet,cost){return Boolean(wallet&&Number.isFinite(wallet.coins)&&Number.isFinite(cost)&&cost>=0&&wallet.coins>=cost);}
