import {WEAPONS,WEAPON_BY_ID,WEAPON_UPGRADES,ECONOMY} from './config.js';

// Pure simulation: no timers, rendering or DOM. Pausing means simply not ticking.
export class Arsenal {
  constructor({emit=()=>{},random=Math.random}={}) {
    this.emit=emit;this.random=random;this.inventory=new Map();this.currentId=WEAPONS[0].id;
    this.cooldown=0;this.reloadState=null;this.emptyCooldown=0;this.bloom=0;
    this.grant(this.currentId);
  }
  get current(){return this.inventory.get(this.currentId);}
  grant(id){const config=WEAPON_BY_ID[id];if(!config||this.inventory.has(id))return false;this.inventory.set(id,{id,magazine:config.magazineSize,reserve:config.reserveAmmo,upgrades:{damage:0,magazine:0,reload:0}});return true;}
  stats(id=this.currentId){
    const base=WEAPON_BY_ID[id],entry=this.inventory.get(id),levels=entry?.upgrades||{};
    if(!base)return null;
    return {...base,damage:Math.round(base.damage*(1+(levels.damage||0)*.18)),magazineSize:Math.round(base.magazineSize*(1+(levels.magazine||0)*.25)),reloadTime:Number((base.reloadTime*(1-(levels.reload||0)*.12)).toFixed(2))};
  }
  buy(id,wallet,round){const config=WEAPON_BY_ID[id];if(!config||this.inventory.has(id)||round<config.unlockRound||wallet.coins<config.price)return false;wallet.coins-=config.price;this.grant(id);this.equip(id);this.emit({type:'purchase',id,cost:config.price});return true;}
  equip(id){
    if(id===this.currentId||!this.inventory.has(id))return false;
    this.cancelReload();this.currentId=id;this.bloom=0;
    // Switching never resets the shared fire clock: no alternating-gun exploit.
    this.cooldown=Math.max(this.cooldown,.16);this.emit({type:'equip',id});return true;
  }
  cycle(direction){const ids=[...this.inventory.keys()],index=ids.indexOf(this.currentId);return this.equip(ids[(index+direction+ids.length)%ids.length]);}
  reload(){
    const entry=this.current,config=this.stats();
    if(this.reloadState||entry.magazine>=config.magazineSize||entry.reserve<=0)return false;
    this.reloadState={id:entry.id,remaining:config.reloadTime,total:config.reloadTime};
    this.emit({type:'reload-start',id:entry.id});return true;
  }
  cancelReload(){if(!this.reloadState)return false;this.reloadState=null;this.emit({type:'reload-cancel'});return true;}
  tick(dt){
    if(!Number.isFinite(dt)||dt<0)return;
    this.cooldown=Math.max(0,this.cooldown-dt);this.emptyCooldown=Math.max(0,this.emptyCooldown-dt);this.bloom=Math.max(0,this.bloom-dt*3.5);
    if(this.reloadState){this.reloadState.remaining-=dt;if(this.reloadState.remaining<=0){const entry=this.current,capacity=this.stats().magazineSize;const transfer=Math.min(capacity-entry.magazine,entry.reserve);entry.magazine+=transfer;entry.reserve-=transfer;this.reloadState=null;this.emit({type:'reload-end',id:entry.id,transfer});}}
  }
  fire({aiming=false}={}){
    if(this.reloadState||this.cooldown>1e-7)return null;
    const entry=this.current,config=this.stats();
    if(entry.magazine===0){if(this.emptyCooldown<=0){this.emit({type:'empty'});this.emptyCooldown=.45;}this.reload();return null;}
    entry.magazine--;this.cooldown=1/config.fireRate;this.bloom=Math.min(1,this.bloom+.14);
    const shot={...config,critical:this.random()<config.criticalChance,spread:aiming?config.aimSpread:config.spread*(1+this.bloom*.4)};
    this.emit({type:'shot',shot});
    // Empty magazines request reload on the next trigger; the final shot still lands instantly.
    return shot;
  }
  addAmmo(fraction=ECONOMY.ammoPickupFraction){let added=0;for(const entry of this.inventory.values()){const config=this.stats(entry.id),amount=Math.min(config.maxReserve-entry.reserve,Math.ceil(config.magazineSize*fraction));entry.reserve+=amount;added+=amount;}return added;}
  refill(wallet,round){const cost=ECONOMY.ammoShopBase+round*ECONOMY.ammoShopRoundScale;const entry=this.current,config=this.stats();if(wallet.coins<cost||entry.reserve===config.maxReserve)return false;wallet.coins-=cost;entry.reserve=config.maxReserve;this.emit({type:'refill',cost});return true;}
  upgradeCost(kind,id=this.currentId){const config=WEAPON_UPGRADES[kind],entry=this.inventory.get(id);if(!config||!entry||entry.upgrades[kind]>=config.max)return null;return Math.round(config.baseCost*Math.pow(config.costScale,entry.upgrades[kind])*(1+WEAPON_BY_ID[id].unlockRound*.08));}
  upgrade(kind,wallet){const cost=this.upgradeCost(kind);if(cost===null||wallet.coins<cost)return false;wallet.coins-=cost;this.current.upgrades[kind]++;this.emit({type:'weapon-upgrade',kind,cost});return true;}
  nextStats(kind){if(this.upgradeCost(kind)===null)return null;this.current.upgrades[kind]++;const next=this.stats();this.current.upgrades[kind]--;return next;}
}
