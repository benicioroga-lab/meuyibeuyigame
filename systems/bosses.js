import * as THREE from 'three';
import {createEnemy,animateEnemy} from './enemies.js';
import {eliteModifiers} from './enemy-config.js';

export const BOSS_ARCHETYPES={
  conductor:{id:'conductor',name:'O Regente',subtitle:'A voz da Liga do Ruído',hp:1100,damage:22,color:'#c3a6ef',speed:1.65,maxSpeed:2.8,scale:1.9,pattern:['pulse','beam','summon','pulse']},
  furnace:{id:'furnace',name:'Fornalha',subtitle:'O coração da fundição',hp:1300,damage:27,color:'#f3a76a',speed:1.25,maxSpeed:2.3,scale:2.05,pattern:['mortar','slam','charge','mortar']},
};
export function bossPhase(health,maxHealth){const ratio=health/Math.max(1,maxHealth);return ratio>.7?1:ratio>.35?2:3;}
export function bossStats(archetype,round=5,{health=1,damage=1,chaos=0}={}){
  const config=BOSS_ARCHETYPES[archetype]||BOSS_ARCHETYPES.conductor,stage=Math.max(0,round-5);
  return {...config,hp:Math.round(config.hp*(1+Math.min(stage,50)*.045)*Math.max(.4,health)),damage:Math.round(config.damage*(1+Math.min(stage,45)*.015)*Math.max(.4,damage)),speed:Math.min(config.maxSpeed,config.speed+Math.min(stage,30)*.025),chaos:Math.max(0,Math.min(5,chaos)),resist:{kinetic:.04,corrosive:-.15},attackRange:3.8,type:'boss',aggression:1};
}
const cylinder=new THREE.CylinderGeometry(.25,.25,.72,10),box=new THREE.BoxGeometry(1,1,1),discGeometry=new THREE.CircleGeometry(1,48),ringGeometry=new THREE.RingGeometry(.95,1,48),beamGeometry=new THREE.PlaneGeometry(1,1);
const asVector=value=>value?.clone?value.clone():new THREE.Vector3(value?.x||0,value?.y||0,value?.z||0);
function positionOf(zone){return asVector(zone.position||zone.center);}
function heightAt(navigation,x,z,y){const value=navigation.heightAt?.(x,z,y);return Number.isFinite(value)?value:y;}

// Bosses share the exact body raycasts and damage pipeline of regular enemies.
// Only the encounter controller owns the phase logic, warning geometry and gates.
export class BossSystem {
  constructor({scene,player,enemies,navigation,world,combat,onReward=()=>{},announce=()=>{},audio=null,hud=null,getRound=()=>1,hurtPlayer=()=>{},getModifiers=()=>({}),emit=()=>{}}){
    Object.assign(this,{scene,player,enemies,navigation,world,combat,onReward,announce,audio,hud,getRound,hurtPlayer,getModifiers,emit});
    this.activeBoss=null;this.activeZone=null;this.telegraphs=[];this.defeatedZones=new Map();this.encounterSequence=0;this.clock=0;this.hudClock=0;this.disposed=false;
  }
  getBoss(){return this.activeBoss;}
  zones(){return this.world?.bossZones||this.world?.zones?.filter(zone=>zone.kind==='boss')||[];}
  available(zone){return this.getRound()>=(zone.unlockRound||5)&&this.getRound()>=(this.defeatedZones.get(zone.id)||0);}
  setGates(zone,closed){for(const id of zone.gateIds||[zone.gateId].filter(Boolean))this.world?.setGate?.(id,closed);}
  play(type){const audio=typeof this.audio==='function'?this.audio():this.audio,cue=type==='start'?'boss-start':type==='phase'?'boss-phase':type==='victory'?'boss-kill':'impact';if(audio?.play)audio.play(cue);else this.combat?.effects?.sound?.(cue);}
  start(zoneOrId,{worldBoss=false}={}){
    if(this.disposed||this.activeBoss||this.player.health<=0)return false;
    const zone=typeof zoneOrId==='string'?this.zones().find(item=>item.id===zoneOrId):zoneOrId;if(!zone||!this.available(zone))return false;
    const options=this.getModifiers()||{},config=bossStats(zone.archetype||'conductor',this.getRound(),options),center=positionOf(zone),position=center.clone();
    position.z+=Math.min(3,zone.radius*.25);position.y=heightAt(this.navigation,position.x,position.z,center.y);this.navigation.freePosition(position,.8);
    const enemy=createEnemy(this.scene,{x:position.x,y:position.y,z:position.z,type:'captain',round:this.getRound(),seed:101+this.encounterSequence++,stats:config,boss:true,elite:config.chaos>1?eliteModifiers(this.encounterSequence,Math.min(2,Math.floor(config.chaos/2))):null});
    Object.assign(enemy,{bossId:config.id,bossManaged:true,active:true,defeated:false,phase:1,attackIndex:0,bossCooldown:2.2,recovery:0,zoneId:zone.id,worldBoss});
    this.decorate(enemy,config);this.activeBoss=enemy;this.activeZone=zone;this.enemies.push(enemy);if(!worldBoss)this.setGates(zone,true);this.clock=0;
    this.announce(worldBoss?'CAÇADA AO BOSS':config.name.toUpperCase(),worldBoss?`${config.name} avistado em ${zone.name||zone.id}`:config.subtitle);this.play('start');this.emit('boss-start',{boss:enemy,zone});this.updateHUD();return true;
  }
  decorate(enemy,config){
    const material=new THREE.MeshStandardMaterial({color:config.color,metalness:.3,roughness:.58}),dark=new THREE.MeshStandardMaterial({color:'#29353d',metalness:.25,roughness:.7});enemy.ownResources.push(material,dark);
    const add=(geometry,mat,position,scale)=>{const part=new THREE.Mesh(geometry,mat);part.position.set(...position);part.scale.set(...scale);part.castShadow=true;part.userData.enemy=enemy;part.userData.zone='body';enemy.rig.add(part);enemy.hitMeshes.push(part);return part;};
    if(config.id==='conductor')for(const side of [-1,1]){
      add(box,dark,[side*.45,1.35,-.34],[.35,.95,.35]);
      for(const y of [1.12,1.52]){const speaker=add(cylinder,material,[side*.45,y,-.53],[.48,.13,.48]);speaker.rotation.x=Math.PI/2;}
      const antenna=add(box,material,[side*.45,2.04,-.34],[.045,.75,.045]);antenna.rotation.z=side*.13;
    }else for(const side of [-1,1]){const chamber=add(cylinder,dark,[side*.42,1.27,-.27],[1.05,1.3,1.05]);for(const y of [1.12,1.4])add(box,material,[side*.42,y,-.535],[.18,.06,.04]);chamber.rotation.z=side*.08;}
  }
  createWarning(kind,point,radius,duration,damage,extra={}){
    if(this.telegraphs.length>=14)return;
    const group=new THREE.Group(),color=this.activeBoss?.config.color||'#edac73';group.position.copy(point);group.position.y+=.045;
    const material=new THREE.MeshBasicMaterial({color,transparent:true,opacity:.15,side:THREE.DoubleSide,depthWrite:false}),edgeMaterial=material.clone();edgeMaterial.opacity=.72;
    const disc=new THREE.Mesh(kind==='beam'?beamGeometry:discGeometry,material),edge=new THREE.Mesh(kind==='beam'?beamGeometry:ringGeometry,edgeMaterial);
    disc.rotation.x=edge.rotation.x=-Math.PI/2;
    if(kind==='beam'){
      const distance=extra.from.distanceTo(extra.to);group.position.copy(extra.from).add(extra.to).multiplyScalar(.5);group.position.y=point.y+.06;
      group.rotation.y=Math.atan2(extra.to.x-extra.from.x,extra.to.z-extra.from.z);disc.scale.set(radius*2,distance,1);edge.scale.set(radius*2+.13,distance+.08,1);edge.position.y=-.01;
    }else{disc.scale.setScalar(radius);edge.scale.setScalar(radius);}
    group.add(edge,disc);this.scene.add(group);
    const warning={kind,point:point.clone(),radius,duration,damage,age:0,group,disc,edge,materials:[material,edgeMaterial],...extra};this.telegraphs.push(warning);return warning;
  }
  clearWarnings(){for(const warning of this.telegraphs){warning.group.removeFromParent();for(const material of warning.materials)material.dispose();}this.telegraphs.length=0;}
  damagedAt(point,radius,damage,{jumpable=false,from=point}={}){
    const pos=this.player.pos,floor=heightAt(this.navigation,pos.x,pos.z,pos.y);
    if(Math.hypot(pos.x-point.x,pos.z-point.z)>radius||Math.abs(pos.y-point.y)>2.6||jumpable&&pos.y>floor+.55)return false;
    const origin=from.clone().add(new THREE.Vector3(0,.65,0)),target=pos.clone().add(new THREE.Vector3(0,.7,0));
    if(this.combat?.hitWorld&&!this.combat.hitWorld.lineOfSight(origin,target))return false;
    this.hurtPlayer(damage,new THREE.Vector3(pos.x-from.x,0,pos.z-from.z).normalize());return true;
  }
  resolveWarning(warning){
    const effects=this.combat?.effects;effects?.nova?.(warning.point,warning.kind==='pulse'?'#b9d5ff':'#f6b77f',warning.radius);this.play('impact');
    if(warning.kind==='beam'){
      const segment=warning.to.clone().sub(warning.from),length=segment.lengthSq();const t=Math.max(0,Math.min(1,this.player.pos.clone().sub(warning.from).dot(segment)/Math.max(.01,length))),closest=warning.from.clone().addScaledVector(segment,t);
      this.damagedAt(closest,warning.radius,warning.damage,{from:warning.from});effects?.beam?.(warning.from.clone().add(new THREE.Vector3(0,.5,0)),warning.to.clone().add(new THREE.Vector3(0,.5,0)),'#dabafa',.25,3);
    }else if(warning.kind==='pulse'){
      // A radial ground shock can be jumped or escaped. The warning always precedes damage.
      this.damagedAt(warning.point,warning.radius,warning.damage,{jumpable:true});
    }else this.damagedAt(warning.point,warning.radius,warning.damage);
  }
  updateWarnings(dt){
    for(let index=this.telegraphs.length-1;index>=0;index--){const warning=this.telegraphs[index];warning.age+=dt;const progress=Math.min(1,warning.age/warning.duration);warning.disc.material.opacity=.09+progress*.21;warning.edge.material.opacity=.45+Math.sin(progress*Math.PI*5)*.18;
      if(warning.age>=warning.duration){this.resolveWarning(warning);warning.group.removeFromParent();for(const material of warning.materials)material.dispose();this.telegraphs.splice(index,1);}
    }
  }
  summon(boss){
    let added=0;const alive=this.enemies.filter(enemy=>!enemy.disabled).length,existing=this.enemies.filter(enemy=>enemy.bossSummoner===boss&&!enemy.disabled).length;
    const total=Math.min(2+(boss.phase>1?1:0),Math.max(0,32-alive),Math.max(0,5-existing)),center=positionOf(this.activeZone);
    for(let i=0;i<total;i++){
      const angle=(boss.attackIndex+i)*2.399,position=center.clone().add(new THREE.Vector3(Math.sin(angle)*4,0,Math.cos(angle)*4));position.y=heightAt(this.navigation,position.x,position.z,center.y);this.navigation.freePosition(position,.45);
      const minion=createEnemy(this.scene,{x:position.x,y:position.y,z:position.z,type:boss.phase===3&&i===0?'shield':'grunt',round:this.getRound(),seed:boss.seed+i+boss.attackIndex*3,roundEnemy:false});minion.bossSummoner=boss;minion.owner=null;this.enemies.push(minion);added++;
    }
    this.emit('boss-summon',{boss,count:added});return added;
  }
  attack(boss){
    const config=boss.config,phase=boss.phase,kind=config.pattern[boss.attackIndex++%config.pattern.length],position=boss.g.position.clone(),target=this.player.pos.clone(),zone=this.activeZone,chaos=config.chaos||0;
    const warningTime=Math.max(.65,1.25-(phase-1)*.17),damage=config.damage*(1+(phase-1)*.12);boss.attackTime=.7;boss.velocity.multiplyScalar(.15);
    if(kind==='summon'){this.summon(boss);boss.recovery=1.3;}
    if(kind==='pulse'||kind==='slam')this.createWarning('pulse',position,kind==='slam'?4.3:4.8+phase*.55,warningTime,damage,{jumpable:true});
    if(kind==='beam'||kind==='charge'){
      const from=position.clone(),direction=target.clone().sub(from).setY(0).normalize(),to=from.clone().addScaledVector(direction,Math.min(16,position.distanceTo(target)+3));to.y=from.y;
      this.createWarning('beam',from,kind==='charge'?1.2:.78,warningTime,damage*1.12,{from,to});
      if(kind==='charge'){boss.chargeTarget=target;boss.chargeDelay=warningTime;boss.chargeTime=1.15;}
    }
    if(kind==='mortar')for(let i=0;i<2+phase+(chaos>=3?1:0);i++){
      const angle=i*2.4+boss.attackIndex,point=target.clone().add(new THREE.Vector3(i?Math.sin(angle)*2.4:0,0,i?Math.cos(angle)*2.4:0)),center=positionOf(zone);
      const offset=point.clone().sub(center).setY(0);if(offset.length()>zone.radius-1)point.copy(center).add(offset.setLength(zone.radius-1));point.y=heightAt(this.navigation,point.x,point.z,center.y);
      this.createWarning('mortar',point,1.75,warningTime+i*.16,damage*.78);
    }
    if(phase===3&&chaos>0&&kind!=='mortar')this.createWarning('mortar',target,1.6,1.65,damage*.7);
    boss.bossCooldown=(phase===1?3.5:phase===2?2.9:2.45)+warningTime;boss.vulnerableTime=warningTime+1.1;
    this.emit('boss-attack',{boss,kind,phase,duration:warningTime});
  }
  finish(){
    const boss=this.activeBoss,zone=this.activeZone;if(!boss||boss.rewarded)return;
    boss.rewarded=true;boss.active=false;boss.defeated=true;boss.disabled=boss.dead=true;boss.health=0;boss.deathTime=0;boss.bossManaged=false;
    this.clearWarnings();if(!boss.worldBoss)this.setGates(zone,false);this.defeatedZones.set(zone.id,this.getRound()+10);
    // Summons leave with their boss. They do not add hidden enemies to round accounting.
    for(const minion of this.enemies)if(minion.bossSummoner===boss&&!minion.disabled){minion.disabled=minion.dead=true;minion.health=0;minion.deathTime=0;}
    const reward={type:'boss',bossId:boss.bossId,zoneId:zone.id,boss,worldBoss:boss.worldBoss,position:boss.g.position.clone(),round:this.getRound(),rarity:'legendary',permanentCurrency:3+Math.floor(this.getRound()/10),coins:350+this.getRound()*25,blueprint:true};
    this.activeBoss=null;this.activeZone=null;this.play('victory');this.announce('BOSS DERROTADO',`${boss.config.name} · espólio lendário`);this.emit('boss-defeated',reward);this.onReward(reward);this.updateHUD();
  }
  onEnemyKilled(enemy){if(enemy===this.activeBoss)this.finish();}
  abort(){
    const boss=this.activeBoss;if(!boss)return;this.clearWarnings();if(!boss.worldBoss)this.setGates(this.activeZone,false);boss.active=false;boss.disabled=boss.dead=true;boss.health=0;boss.bossManaged=false;boss.deathTime=0;
    for(const minion of this.enemies)if(minion.bossSummoner===boss&&!minion.disabled){minion.disabled=minion.dead=true;minion.health=0;}
    this.activeBoss=null;this.activeZone=null;this.updateHUD();
  }
  update(dt,time=0){
    if(this.disposed)return;this.clock+=dt;
    if(this.player.health<=0){this.abort();return;}
    const boss=this.activeBoss;
    if(!boss){for(const zone of this.zones()){const center=positionOf(zone);if(this.available(zone)&&Math.hypot(this.player.pos.x-center.x,this.player.pos.z-center.z)<Math.max(2,zone.radius*.72)&&Math.abs(this.player.pos.y-center.y)<2.2){this.start(zone);break;}}return;}
    if(boss.disabled||boss.health<=0){this.finish();return;}
    // A remotely announced hunt does not lock an arena around an absent player or
    // rain attacks across the entire map. Approach it to begin the encounter.
    if(boss.worldBoss&&boss.g.position.distanceTo(this.player.pos)>30){this.clearWarnings();boss.velocity.multiplyScalar(Math.exp(-dt*8));animateEnemy(boss,dt,this.combat?.game?.camera,this.navigation);this.updateHUD();return;}
    const phase=bossPhase(boss.health,boss.maxHealth);
    if(phase!==boss.phase){boss.phase=phase;this.clearWarnings();boss.bossCooldown=1.4;boss.recovery=.8;boss.chargeTime=0;this.announce(phase===3?'FÚRIA FINAL':`${boss.config.name.toUpperCase()} · FASE ${phase}`,'Observe o chão. Use os corredores.');this.play('phase');this.emit('boss-phase',{boss,phase});}
    this.updateWarnings(dt);boss.bossCooldown-=dt;boss.recovery=Math.max(0,boss.recovery-dt);boss.vulnerableTime=Math.max(0,boss.vulnerableTime-dt);
    for(const timer of ['slowTime','stunTime','freezeTime'])boss[timer]=Math.max(0,(boss[timer]||0)-dt);
    if(boss.chargeTime>0){boss.chargeDelay-=dt;if(boss.chargeDelay<=0){boss.chargeTime-=dt;this.navigation.move(boss,boss.chargeTarget,boss.config.maxSpeed,dt,.68*boss.config.scale);}}
    else if(!this.telegraphs.length&&boss.recovery<=0&&boss.stunTime<=0&&boss.freezeTime<=0){
      const distance=boss.g.position.distanceTo(this.player.pos);
      if(distance>4.5)this.navigation.move(boss,this.player.pos,Math.min(boss.config.maxSpeed,boss.config.speed*(1+(phase-1)*.12))*(boss.slowTime>0?Math.max(.6,boss.slowFactor):1),dt,.65*boss.config.scale);
      else boss.velocity.multiplyScalar(Math.exp(-dt*8));
    }else boss.velocity.multiplyScalar(Math.exp(-dt*10));
    const targetAngle=Math.atan2(this.player.pos.x-boss.g.position.x,this.player.pos.z-boss.g.position.z),delta=THREE.MathUtils.euclideanModulo(targetAngle-boss.g.rotation.y+Math.PI,Math.PI*2)-Math.PI;boss.g.rotation.y+=delta*Math.min(1,dt*3);
    if(boss.bossCooldown<=0&&boss.freezeTime<=0)this.attack(boss);
    animateEnemy(boss,dt,this.combat?.game?.camera,this.navigation);
    this.hudClock-=dt;if(this.hudClock<=0){this.hudClock=.1;this.updateHUD();}
  }
  updateHUD(){
    const boss=this.activeBoss,root=this.hud||(typeof document!=='undefined'?document.getElementById('bossHud'):null);if(!root)return;
    const hidden=!boss||boss.worldBoss&&boss.g.position.distanceTo(this.player.pos)>30;root.hidden=hidden;root.setAttribute?.('aria-hidden',String(hidden));if(hidden)return;
    const set=(selector,value)=>{const node=root.querySelector?.(selector);if(node)node.textContent=value;};set('[data-boss-name]',boss.config.name);set('[data-boss-phase]',`FASE ${boss.phase} / 3`);set('[data-boss-health]',`${Math.ceil(boss.health)} / ${boss.maxHealth}`);
    const fill=root.querySelector?.('[data-boss-fill]');if(fill)fill.style.width=`${Math.max(0,boss.health/boss.maxHealth)*100}%`;
  }
  dispose(){if(this.disposed)return;this.abort();this.clearWarnings();this.disposed=true;}
}
