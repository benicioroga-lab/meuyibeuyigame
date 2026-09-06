import * as THREE from 'three';
import {Arsenal} from './arsenal.js';
import {HitWorld} from './hit-detection.js';
import {CombatEffects,WeaponView} from './combat-effects.js';

const canonicalEffect=value=>({fire:'burn',shock:'chain',cryo:'frost',explosive:'explosive',corrosion:'corrosive'}[value]||value||'kinetic');
const effectColor=effect=>({burn:'#ffb474',chain:'#95e5ff',frost:'#c3dcff',corrosive:'#bce77e',explosive:'#ffd494'}[canonicalEffect(effect)]||'#e6d8b8');
const centerOf=enemy=>enemy.g.position.clone().add(new THREE.Vector3(0,enemy.config?.scale||1,0));

export class CombatSystem {
  constructor(game){
    this.game=game;this.recoilPitch=0;this.recoilYaw=0;this.shotIndex=0;this.unlocked=new Set(['biscuit']);this.hudClock=0;this.killStreak=0;this.streakRemaining=0;
    this.hitWorld=new HitWorld({colliders:game.colliders,props:game.props,enemies:game.enemies,getBoss:game.getBoss,getWorld:()=>game.getWorld?.()||game.world});
    this.effects=new CombatEffects({scene:game.scene,camera:game.camera,getAudio:game.getAudio,getAudioEngine:game.getAudioEngine,getVolume:game.getVolume,reduceMotion:()=>game.settings().reduceMotion,showNumbers:()=>game.settings().damageNumbers!==false});
    this.view=new WeaponView(game.camera,game.dog);
    this.arsenal=new Arsenal({emit:event=>this.event(event),getModifiers:()=>this.modifiers()});this.view.equip(this.arsenal.stats());
    this.updateHUD();
  }
  modifiers(){return this.game.getModifiers?.()||this.game.getRunModifiers?.()||{};}
  event(event){
    if(event.type==='shot')return;
    if(event.type==='equip'){this.view.equip(this.arsenal.stats());this.effects.sound('equip');this.game.toast(this.arsenal.stats().name);}
    if(['reload-start','reload-end','empty'].includes(event.type))this.effects.sound(event.type,this.arsenal?.stats());
    if(event.type==='reload-start'){this.view.inspection=0;this.reloadCuePhase=0;}
    if(['purchase','weapon-upgrade','refill','forge','refine','reroll','attachment-install','attachment'].includes(event.type)){if(event.cost)this.game.reward(-event.cost);this.effects.sound(['forge','refine'].includes(event.type)?'forge':'purchase');}
    this.updateHUD();
  }
  muzzle(){
    // Camera determines aim; the physical harness still cannot shoot through nearby cover.
    const {player}=this.game,origin=player.pos.clone();origin.y+=1.05;
    const forward=new THREE.Vector3(Math.sin(player.cameraYaw),0,Math.cos(player.cameraYaw));
    const obstruction=this.hitWorld.surfaces(origin,forward,.58);
    return origin.addScaledVector(forward,obstruction?Math.max(0,obstruction.distance-.03):.58);
  }
  fire({burstFollowup=false}={}){
    if(!this.game.active())return false;
    this.game.syncAim?.();
    this.arsenal.setModifiers?.(this.modifiers());
    const shot=this.arsenal.fire({aiming:this.game.player.aiming,burstFollowup});if(!shot){this.updateHUD();return false;}
    shot.effect=canonicalEffect(shot.element||shot.effect);
    this.shotIndex++;this.effects.counter.shots++;
    const pellets=Math.max(1,Math.min(16,Math.round(shot.pellets||1))),repeats=1+Math.min(2,shot.bonusShots||0),muzzle=this.muzzle();
    const visualOrigin=this.game.player.thirdPerson?muzzle:this.view.muzzlePosition();
    for(let repeat=0;repeat<repeats;repeat++)for(let pellet=0;pellet<pellets;pellet++){
      const result=this.hitWorld.aim(this.game.camera,muzzle,shot);let penetration=1;
      for(const hit of result.hits){
        if(hit.kind==='enemy'){
          if(hit.entity.disabled)continue;
          const headshot=hit.zone==='head',critical=Boolean(shot.critical||headshot),distanceFalloff=shot.family==='shotgun'?Math.max(.3,1-Math.max(0,hit.distance-12)/Math.max(15,shot.range)):1;
          const amount=shot.damage/pellets*penetration*distanceFalloff*(critical?(shot.criticalMultiplier||1.65):1);
          const detail=this.resolveDamage(hit.entity,amount,{critical,headshot,zone:hit.zone,source:'weapon',weaponId:shot.weaponId||shot.id,effect:shot.effect,point:hit.point,direction:result.direction,headshotExplosion:shot.headshotExplosion});
          if(!detail.shielded){
            if(!hit.entity.disabled)this.applyStatus(hit.entity,shot);
            if(shot.effect==='chain')this.chain(hit.entity,shot.damage/pellets*(shot.chainDamage||.4),shot.chainTargets||2,shot.chainRadius||5,'weapon',shot.weaponId||shot.id);
            if(shot.effect==='frost'&&shot.radius)this.area(hit.point,shot.radius,shot.damage/pellets*(shot.splashDamage||.35),{...shot,effect:'frost',exclude:hit.entity});
          }
          penetration*=.72;
          // A shield is a physical shot surface: piercing begins again only after a later shot sees a broken shield.
          if(detail.shielded){this.effects.impact(hit,'#a3d6ff');result.point=hit.point;break;}
        }else if(hit.kind==='boss'){
          const amount=shot.damage/pellets*(shot.critical?(shot.criticalMultiplier||1.65):1);this.game.damageBoss?.(amount);this.effects.damageNumber(hit.entity,amount,{critical:shot.critical});this.effects.hit({critical:shot.critical,kill:hit.entity.defeated});
        }else if(hit.kind==='object')this.game.hitProp?.(hit.entity,shot.damage/pellets);
        this.effects.impact(hit,effectColor(shot.effect));
      }
      if(shot.effect==='explosive'){const first=result.hits[0],splashOrigin=result.point.clone();if(first?.normal)splashOrigin.addScaledVector(first.normal,.05);this.area(splashOrigin,shot.radius||2.5,shot.damage/pellets*(shot.splashDamage||.6),{effect:'explosive',weaponId:shot.weaponId||shot.id,source:'weapon',exclude:first?.kind==='enemy'?first.entity:null});}
      // Shotgun tracers share a small budget; every pellet still resolves independently and immediately.
      if(pellet<4)this.effects.beam(visualOrigin,result.point,shot.color||effectColor(shot.effect),shot.fireRate>8?.04:.07,shot.family==='heavy'||shot.family==='sniper'?1.5:1);
    }
    this.view.recoil(shot);this.effects.shell(this.view.shellPosition(),this.game.camera,shot);
    this.effects.sound('shot',shot);
    if(!this.game.settings().reduceMotion){this.recoilPitch=Math.min(.085,this.recoilPitch+(shot.recoil||0));this.recoilYaw+=(this.shotIndex%2?1:-1)*(shot.recoil||0)*.14;}
    this.game.player.firing=.14;this.updateHUD();return true;
  }
  preview(){const config=this.arsenal.stats();return this.hitWorld.aim(this.game.camera,this.muzzle(),{...config,spread:0,pierce:1});}
  damage(enemy,amount,options={}){return this.resolveDamage(enemy,amount,options).actual;}
  resolveDamage(enemy,amount,{critical=false,headshot=false,zone='torso',source='weapon',weaponId=null,effect='kinetic',point=null,direction=null,noExplosion=false,headshotExplosion=0,periodic=false}={}){
    const detail={enemy,actual:0,damage:0,killed:false,headshot,critical,zone,source,weaponId,effect:canonicalEffect(effect),shielded:false};
    if(!enemy||enemy.disabled||!Number.isFinite(amount)||amount<=0)return detail;
    effect=detail.effect;const shield=enemy.shieldHealth??enemy.shield?.health??0;
    enemy.hitTime=.18;enemy.healthTimer=2.2;enemy.hitRegion=zone;enemy.hitDirection=direction?.clone()||new THREE.Vector3();enemy.lastHit={zone,critical,direction:enemy.hitDirection,source};
    if(zone==='shield'&&shield>0){
      const absorbed=Math.min(shield,Math.max(1,Math.round(amount*(effect==='corrosive'?1.8:1))));
      enemy.shieldHealth=shield-absorbed;if(enemy.shield)enemy.shield.health=enemy.shieldHealth;
      enemy.shieldBroken=enemy.shieldHealth<=0;if(enemy.shieldBroken){if(enemy.shield?.mesh)enemy.shield.mesh.visible=false;enemy.stunTime=Math.max(enemy.stunTime||0,.55);this.effects.nova(point||centerOf(enemy),'#abd9ff',.7);this.effects.sound('impact');}
      detail.shielded=true;detail.damage=absorbed;this.effects.damageNumber(enemy,absorbed,{source,shield:true});this.effects.hit({shield:true});return detail;
    }
    const resistance=THREE.MathUtils.clamp(enemy.config?.resist?.[effect]||0,-.5,.85);
    const corrosion=enemy.corrosiveTime>0?.5:1,vulnerability=enemy.vulnerableTime>0?1.2:1,shieldBuff=enemy.shieldedTime>0?.85:1;
    const rawDamage=amount*(1-resistance*corrosion)*vulnerability*shieldBuff,damage=periodic?Math.max(.001,Math.round(rawDamage*1000)/1000):Math.max(1,Math.round(rawDamage)),actual=Math.min(enemy.health,damage);
    enemy.health=Math.max(0,enemy.health-damage);detail.actual=actual;detail.damage=damage;detail.killed=enemy.health<=0;
    const ratio=enemy.health/enemy.maxHealth;if(enemy.barFill){enemy.barFill.scale.x=ratio;enemy.barFill.position.x=-(1-ratio)*.43;}
    if(zone==='leg'&&!enemy.boss){enemy.stumbleTime=Math.max(enemy.stumbleTime||0,.28);enemy.stunTime=Math.max(enemy.stunTime||0,.09);}
    this.effects.damageNumber(enemy,actual,{critical,kill:detail.killed,source});
    if(source==='weapon')this.effects.hit({critical,headshot,kill:detail.killed});
    const selfRemoval=source==='self'||source==='despawn'||source==='bossMinionDespawn';
    if(!selfRemoval)this.game.onDamageDealt?.(actual,detail);
    if(detail.killed){
      enemy.disabled=enemy.dead=true;enemy.deathTime=0;if(enemy.healthBar)enemy.healthBar.visible=false;
      this.effects.burst(point||centerOf(enemy),critical?'#f9d489':'#b8d1b3',6,1.7);
      if(!selfRemoval)this.arsenal?.onKill?.(detail);this.game.onKill?.(enemy,source,detail);
      if(selfRemoval)return detail;
      this.killStreak=this.streakRemaining>0?this.killStreak+1:1;this.streakRemaining=2.8;
      if(source==='weapon'&&this.killStreak>=2){this.effects.accolade(this.killStreak===2?'DUPLA ELIMINAÇÃO':this.killStreak===3?'TRIPLA ELIMINAÇÃO':this.killStreak===5?'DOMÍNIO TOTAL':`${this.killStreak} EM SEQUÊNCIA`);if([2,3,5,8].includes(this.killStreak))this.effects.sound('multikill',{count:this.killStreak});}
      const modifier=headshotExplosion||this.modifiers().headshotExplosion;
      if(headshot&&modifier&&!noExplosion)this.area(point||centerOf(enemy),2.6,amount*Math.max(0,Number(modifier)||1),{effect:'explosive',source,weaponId,exclude:enemy,noExplosion:true});
      else if(enemy.burnTime>0&&!noExplosion)this.area(centerOf(enemy),2,12,{effect:'burn',source,weaponId,exclude:enemy,noExplosion:true});
    }
    return detail;
  }
  applyStatus(enemy,config){
    if(enemy.disabled)return;const effect=canonicalEffect(config.element||config.effect);
    if(effect==='burn'){if(!(enemy.burnTime>0))enemy.burnTick=.5;enemy.burnTime=Math.max(enemy.burnTime||0,config.burnDuration||3);enemy.burnDamage=Math.max(enemy.burnDamage||0,config.burnDamage||Math.max(4,config.damage*.14)||5);enemy.burnSource=config.source||'weapon';enemy.burnWeaponId=config.weaponId||null;}
    if(effect==='corrosive'){if(!(enemy.corrosiveTime>0))enemy.corrosiveTick=.5;enemy.corrosiveTime=Math.max(enemy.corrosiveTime||0,config.corrosiveDuration||config.corrosionDuration||4);enemy.corrosiveDamage=Math.max(enemy.corrosiveDamage||0,config.corrosiveDamage||config.corrosionDamage||Math.max(4,(config.damage||20)*.1));enemy.corrosiveSource=config.source||'weapon';enemy.corrosiveWeaponId=config.weaponId||null;}
    if(effect==='frost'){enemy.slowTime=Math.max(enemy.slowTime||0,config.slowDuration||2);enemy.slowFactor=config.slow||.55;enemy.frostStacks=Math.min(4,(enemy.frostStacks||0)+1);if(enemy.frostStacks>=4){enemy.freezeTime=Math.max(enemy.freezeTime||0,enemy.boss?.3:1.15);enemy.stunTime=Math.max(enemy.stunTime||0,enemy.freezeTime);enemy.frostStacks=0;this.effects.burst(centerOf(enemy),'#c8e4ff',4,.4);}}
    if(config.stun)enemy.stunTime=Math.max(enemy.stunTime||0,config.stun);
  }
  area(point,radius,amount,options={}){
    if(!radius||amount<=0)return;
    const candidates=this.game.enemies.filter(enemy=>!enemy.disabled&&enemy!==options.exclude&&centerOf(enemy).distanceTo(point)<radius+(enemy.config?.scale||1)*.6).sort((a,b)=>a.g.position.distanceToSquared(point)-b.g.position.distanceToSquared(point)).slice(0,16);
    for(const enemy of candidates){const center=centerOf(enemy);if(!this.hitWorld.lineOfSight(point,center))continue;this.damage(enemy,amount,{...options,source:options.source||'weapon',point:center,noExplosion:true});this.applyStatus(enemy,options);}
    this.effects.nova(point,effectColor(options.effect),radius);
  }
  chain(first,amount,count,radius,source='weapon',weaponId=null){
    const visited=new Set([first]);let previous=first;
    for(let i=0;i<Math.min(8,count);i++){
      const from=centerOf(previous),candidate=this.game.enemies.filter(e=>!e.disabled&&!visited.has(e)&&centerOf(e).distanceTo(from)<radius).sort((a,b)=>a.g.position.distanceToSquared(from)-b.g.position.distanceToSquared(from)).find(e=>this.hitWorld.lineOfSight(from,centerOf(e)));
      if(!candidate)break;visited.add(candidate);const to=centerOf(candidate);this.effects.beam(from,to,'#a0e5f2',.15,1.5);this.damage(candidate,amount,{source,weaponId,effect:'chain',point:to,noExplosion:true});candidate.stunTime=Math.max(candidate.stunTime||0,.16);previous=candidate;
    }
  }
  reload(){if(!this.game.active())return false;this.arsenal.setModifiers?.(this.modifiers());return this.arsenal.reload();}
  inspect(){if(!this.game.active()||this.arsenal.reloadState||this.arsenal.inspect?.()===false)return false;this.view.inspect();this.effects.sound('inspect');return true;}
  beginFrame(dt){
    if(!Number.isFinite(dt)||dt<=0)return;
    this.arsenal.setModifiers?.(this.modifiers());this.arsenal.tick(dt);this.recoilPitch*=Math.exp(-dt*10);this.recoilYaw*=Math.exp(-dt*13);this.streakRemaining=Math.max(0,this.streakRemaining-dt);
    const reloading=this.arsenal.reloadState;
    if(reloading){const progress=1-reloading.remaining/reloading.total;if(progress>.55&&this.reloadCuePhase<1){this.reloadCuePhase=1;this.effects.sound('reload-insert',this.arsenal.stats());}if(progress>.85&&this.reloadCuePhase<2&&reloading.kind==='empty'){this.reloadCuePhase=2;this.effects.sound('reload-chamber',this.arsenal.stats());}}
    if(this.arsenal.burstRemaining>0)this.fire({burstFollowup:true});
    for(const enemy of this.game.enemies){
      if(enemy.disabled)continue;if(!(enemy.slowTime>0))enemy.frostStacks=0;
      for(const effect of ['burn','corrosive']){
        const timer=`${effect}Time`,tick=`${effect}Tick`;if(!(enemy[timer]>0))continue;
        const activeTime=Math.min(dt,enemy[timer]);enemy[timer]=Math.max(0,enemy[timer]-dt);enemy[tick]=(enemy[tick]??.5)-activeTime;
        while(enemy[tick]<=1e-8&&!enemy.disabled){enemy[tick]+=.5;this.damage(enemy,(enemy[`${effect}Damage`]||0)*.5,{effect,source:enemy[`${effect}Source`]||'weapon',weaponId:enemy[`${effect}WeaponId`],noExplosion:false,periodic:true});if(!enemy.disabled)this.effects.burst(centerOf(enemy),effectColor(effect),2,.4);}
      }
    }
  }
  update(dt){
    this.effects.update(dt);const config=this.arsenal.stats();this.view.equip(config);
    this.view.update(dt,{aiming:this.game.player.aiming,thirdPerson:this.game.player.thirdPerson,active:this.game.active(),reload:this.arsenal.reloadState,velocity:this.game.player.moveVelocity.length(),sprinting:!this.game.player.aiming&&this.game.player.moveVelocity.length()>8,reduceMotion:this.game.settings().reduceMotion,time:this.game.time()});
    this.hudClock-=dt;if(this.hudClock<=0){this.updateHUD();this.hudClock=.06;}
    const spread=this.game.player.aiming?config.aimSpread:config.spread*(1+this.arsenal.bloom*.4),height=globalThis.innerHeight||720;
    const pixels=Math.tan(spread||0)*height/(2*Math.tan(THREE.MathUtils.degToRad(this.game.camera.fov)/2));
    globalThis.document?.querySelector('.crosshair')?.style.setProperty('--spread',`${4+pixels}px`);
  }
  updateHUD(){
    if(!globalThis.document||!this.arsenal)return;const config=this.arsenal.stats(),entry=this.arsenal.current,reload=this.arsenal.reloadState;
    const set=(id,value)=>{const el=document.getElementById(id);if(el&&el.textContent!==String(value))el.textContent=value;};
    set('weaponName',config.name);set('weaponCategory',[config.rarityName||config.rarity,config.manufacturerName||config.manufacturer,config.category].filter(Boolean).join(' · '));set('ammoMagazine',this.modifiers().infiniteAmmo?'∞':entry.magazine);set('ammoReserve',entry.reserve);
    set('weaponElement',config.effect&&config.effect!=='kinetic'?config.effect:'');
    set('reloadStatus',reload?`${reload.kind==='empty'?'RECARGA COMPLETA':'RECARGA TÁTICA'} ${Math.max(0,reload.remaining).toFixed(1)}s`:entry.magazine===0&&entry.reserve===0?'SEM MUNIÇÃO · TAB PARA REPOR':'R · RECARREGAR');
    const meter=document.getElementById('reloadFill');if(meter)meter.style.width=reload?`${(1-reload.remaining/reload.total)*100}%`:'0%';
    document.querySelector('.game-shell')?.classList.toggle('reloading',Boolean(reload));
    const hud=document.getElementById('weaponHud');hud?.classList.toggle('empty',entry.magazine===0);hud?.classList.toggle('reloading',Boolean(reload));hud?.style.setProperty('--weapon-color',config.rarityColor||config.color);
    const metrics=document.getElementById('game');if(metrics){metrics.dataset.shots=String(this.effects.counter.shots);metrics.dataset.hits=String(this.effects.counter.hits);metrics.dataset.kills=String(this.effects.counter.kills);}
  }
  dispose(){this.effects.dispose();this.view.dispose();}
}
