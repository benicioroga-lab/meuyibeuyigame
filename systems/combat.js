import * as THREE from 'three';
import {Arsenal} from './arsenal.js';
import {HitWorld} from './hit-detection.js';
import {CombatEffects,WeaponView} from './combat-effects.js';

export class CombatSystem {
  constructor(game){
    this.game=game;this.recoilPitch=0;this.recoilYaw=0;this.shotIndex=0;this.unlocked=new Set(['biscuit']);this.hudClock=0;
    this.hitWorld=new HitWorld({colliders:game.colliders,props:game.props,enemies:game.enemies,getBoss:game.getBoss});
    this.effects=new CombatEffects({scene:game.scene,camera:game.camera,getAudio:game.getAudio,getAudioEngine:game.getAudioEngine,getVolume:game.getVolume,reduceMotion:()=>game.settings().reduceMotion});
    this.view=new WeaponView(game.camera,game.dog);
    this.arsenal=new Arsenal({emit:event=>this.event(event)});this.view.equip(this.arsenal.stats());
    this.updateHUD();
  }
  event(event){
    if(event.type==='shot')return;
    if(event.type==='equip'){this.view.equip(this.arsenal.stats());this.game.toast(this.arsenal.stats().name);}
    if(['reload-start','reload-end','empty'].includes(event.type))this.effects.sound(event.type);
    if(['purchase','weapon-upgrade','refill'].includes(event.type)){this.game.reward(-event.cost);this.effects.sound('purchase');}
    this.updateHUD();
  }
  muzzle(){
    // The physical origin is on Meyui's harness, even in third person. The FPS model is cosmetic.
    const {player}=this.game,origin=player.pos.clone();origin.y+=1.05;
    const forward=new THREE.Vector3(Math.sin(player.cameraYaw),0,Math.cos(player.cameraYaw));
    const obstruction=this.hitWorld.surfaces(origin,forward,.58);
    return origin.addScaledVector(forward,obstruction?Math.max(0,obstruction.distance-.03):.58);
  }
  fire(){
    if(!this.game.active())return false;
    const shot=this.arsenal.fire({aiming:this.game.player.aiming});if(!shot){this.updateHUD();return false;}
    const result=this.hitWorld.aim(this.game.camera,this.muzzle(),shot);
    this.shotIndex++;this.effects.counter.shots++;
    let penetration=1;
    for(const hit of result.hits){
      if(hit.kind==='enemy'){
        const critical=shot.critical||hit.zone==='head';
        this.damage(hit.entity,shot.damage*penetration*(critical?1.65:1),{critical,source:'weapon',effect:shot.effect,point:hit.point});
        if(!hit.entity.disabled)this.applyStatus(hit.entity,shot);
        if(shot.effect==='chain')this.chain(hit.entity,shot.damage*shot.chainDamage,shot.chainTargets,shot.chainRadius);
        if(shot.effect==='frost')this.area(hit.point,shot.radius,shot.damage*shot.splashDamage,{effect:'frost',slow:shot.slow,slowDuration:shot.slowDuration,exclude:hit.entity});
        penetration*=.72;
      }else if(hit.kind==='boss'){this.game.damageBoss(shot.damage*(shot.critical?1.65:1));this.effects.damageNumber(hit.entity,shot.damage,{critical:shot.critical});this.effects.hit({critical:shot.critical,kill:hit.entity.defeated});}
      else if(hit.kind==='object')this.game.hitProp(hit.entity,shot.damage);
      this.effects.impact(hit,shot.color);
    }
    const visualOrigin=this.game.player.thirdPerson?this.muzzle():this.view.muzzlePosition();
    this.effects.beam(visualOrigin,result.point,shot.color,shot.fireRate>8?.04:.07,shot.category==='PESADA'?2:1);
    this.view.recoil(shot);this.effects.sound('shot',shot);
    if(!this.game.settings().reduceMotion){this.recoilPitch=Math.min(.065,this.recoilPitch+shot.recoil);this.recoilYaw+=(this.shotIndex%2?1:-1)*shot.recoil*.14;}
    this.game.player.firing=.14;this.updateHUD();return true;
  }
  preview(){const config=this.arsenal.stats();return this.hitWorld.aim(this.game.camera,this.muzzle(),{...config,spread:0,pierce:1});}
  damage(enemy,amount,{critical=false,source='weapon',effect='kinetic',point=null,noExplosion=false}={}){
    if(enemy.disabled||amount<=0)return 0;
    const resistance=enemy.config.resist?.[effect]||0,damage=Math.max(1,Math.round(amount*(1-resistance))),actual=Math.min(enemy.health,damage);
    enemy.health=Math.max(0,enemy.health-damage);enemy.hitTime=.18;enemy.healthTimer=2.2;
    const ratio=enemy.health/enemy.maxHealth;enemy.barFill.scale.x=ratio;enemy.barFill.position.x=-(1-ratio)*.43;
    const killed=enemy.health<=0;this.effects.damageNumber(enemy,damage,{critical,kill:killed,source});
    if(source==='weapon')this.effects.hit({critical,kill:killed});
    if(killed){
      enemy.disabled=enemy.dead=true;enemy.deathTime=0;enemy.healthBar.visible=false;
      this.effects.burst(point||enemy.g.position.clone().add(new THREE.Vector3(0,1,0)),critical?'#f9d489':'#b8d1b3',6,1.7);
      this.game.onKill(enemy,source);
      if(enemy.burnTime>0&&!noExplosion){this.area(enemy.g.position.clone().add(new THREE.Vector3(0,.6,0)),2,12,{effect:'burn',source,exclude:enemy,noExplosion:true});}
    }
    return actual;
  }
  applyStatus(enemy,config){
    if(enemy.disabled)return;
    if(config.effect==='burn'){enemy.burnTime=Math.max(enemy.burnTime,config.burnDuration||2);enemy.burnDamage=Math.max(enemy.burnDamage,config.burnDamage||5);enemy.burnSource=config.source||'weapon';}
    if(config.effect==='frost'){enemy.slowTime=Math.max(enemy.slowTime,config.slowDuration||2);enemy.slowFactor=config.slow||.5;}
    if(config.stun)enemy.stunTime=Math.max(enemy.stunTime,config.stun);
  }
  area(point,radius,amount,options={}){
    const candidates=this.game.enemies.filter(enemy=>!enemy.disabled&&enemy!==options.exclude&&enemy.g.position.distanceTo(point)<radius+enemy.config.scale*.6).slice(0,8);
    for(const enemy of candidates){const center=enemy.g.position.clone().add(new THREE.Vector3(0,enemy.config.scale,0));if(!this.hitWorld.lineOfSight(point,center))continue;this.damage(enemy,amount,{...options,source:options.source||'weapon',point:center});this.applyStatus(enemy,options);}
    this.effects.nova(point,options.effect==='frost'?'#b5d7ff':'#ffc07a',radius);
  }
  chain(first,amount,count,radius,source='weapon'){
    const visited=new Set([first]);let previous=first;
    for(let i=0;i<count;i++){
      const from=previous.g.position.clone().add(new THREE.Vector3(0,previous.config.scale,0));
      const candidate=this.game.enemies.filter(e=>!e.disabled&&!visited.has(e)&&e.g.position.distanceTo(previous.g.position)<radius).sort((a,b)=>a.g.position.distanceToSquared(from)-b.g.position.distanceToSquared(from)).find(e=>this.hitWorld.lineOfSight(from,e.g.position.clone().add(new THREE.Vector3(0,e.config.scale,0))));
      if(!candidate)break;visited.add(candidate);
      const to=candidate.g.position.clone().add(new THREE.Vector3(0,candidate.config.scale,0));this.effects.beam(from,to,'#a0e5f2',.15,2);this.damage(candidate,amount,{source,effect:'chain',point:to});candidate.stunTime=Math.max(candidate.stunTime,.16);previous=candidate;
    }
  }
  reload(){if(!this.game.active())return false;return this.arsenal.reload();}
  beginFrame(dt){
    this.arsenal.tick(dt);this.recoilPitch*=Math.exp(-dt*10);this.recoilYaw*=Math.exp(-dt*13);
    for(const enemy of this.game.enemies){if(enemy.disabled||enemy.burnTime<=0)continue;enemy.burnTime=Math.max(0,enemy.burnTime-dt);enemy.burnTick-=dt;if(enemy.burnTick<=0){enemy.burnTick=.5;this.damage(enemy,enemy.burnDamage*.5,{effect:'burn',source:enemy.burnSource,noExplosion:false});if(!enemy.disabled)this.effects.burst(enemy.g.position.clone().add(new THREE.Vector3(0,.7,0)),'#ffbb74',2,.4);}}
  }
  update(dt){
    this.effects.update(dt);const config=this.arsenal.stats();this.view.equip(config);
    this.view.update(dt,{aiming:this.game.player.aiming,thirdPerson:this.game.player.thirdPerson,active:this.game.active(),reload:this.arsenal.reloadState,velocity:this.game.player.moveVelocity.length(),reduceMotion:this.game.settings().reduceMotion,time:this.game.time()});
    this.hudClock-=dt;if(this.hudClock<=0){this.updateHUD();this.hudClock=.06;}
    const spread=this.game.player.aiming?config.aimSpread:config.spread*(1+this.arsenal.bloom*.4);
    const pixels=Math.tan(spread)*innerHeight/(2*Math.tan(THREE.MathUtils.degToRad(this.game.camera.fov)/2));
    document.querySelector('.crosshair').style.setProperty('--spread',`${4+pixels}px`);
  }
  updateHUD(){
    const config=this.arsenal.stats(),entry=this.arsenal.current,reload=this.arsenal.reloadState;
    const set=(id,value)=>{const el=document.getElementById(id);if(el&&el.textContent!==String(value))el.textContent=value;};
    set('weaponName',config.name);set('weaponCategory',config.category);set('ammoMagazine',entry.magazine);set('ammoReserve',entry.reserve);
    set('reloadStatus',reload?`RECARREGANDO ${(Math.max(0,reload.remaining)).toFixed(1)}s`:entry.magazine===0&&entry.reserve===0?'SEM MUNIÇÃO · TAB PARA REPOR':'R · RECARREGAR');
    const meter=document.getElementById('reloadFill');if(meter)meter.style.width=reload?`${(1-reload.remaining/reload.total)*100}%`:'0%';
    document.querySelector('.game-shell')?.classList.toggle('reloading',Boolean(reload));
    document.getElementById('weaponHud')?.classList.toggle('empty',entry.magazine===0);
    document.getElementById('weaponHud')?.classList.toggle('reloading',Boolean(reload));
    const metrics=document.getElementById('game');if(metrics){metrics.dataset.shots=String(this.effects.counter.shots);metrics.dataset.hits=String(this.effects.counter.hits);metrics.dataset.kills=String(this.effects.counter.kills);}
  }
  dispose(){this.effects.dispose();this.view.dispose();}
}
