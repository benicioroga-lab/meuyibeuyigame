import * as THREE from 'three';
import {enemyStats,normalizeElite,FACTION} from './enemy-config.js';

// An original hostile faction, not a population of the neighbourhood. The broken
// amber bars, coloured sport armour, masks and radio packs identify Liga do Ruído.
const geometry={head:new THREE.SphereGeometry(.32,10,8),torso:new THREE.CylinderGeometry(.35,.29,.68,8),limb:new THREE.CapsuleGeometry(.11,.27,3,6),shoe:new THREE.BoxGeometry(.23,.17,.36),eye:new THREE.SphereGeometry(.055,6,5),hand:new THREE.SphereGeometry(.13,7,6),cap:new THREE.CylinderGeometry(.34,.34,.15,10),can:new THREE.CylinderGeometry(.16,.16,.35,8),sole:new THREE.BoxGeometry(.23,.055,.38),stripe:new THREE.BoxGeometry(.035,.53,.025),radio:new THREE.BoxGeometry(.14,.23,.1),antenna:new THREE.CylinderGeometry(.008,.008,.23,5),strap:new THREE.BoxGeometry(.1,.025,.035),badge:new THREE.BoxGeometry(.07,.09,.02),box:new THREE.BoxGeometry(1,1,1),ring:new THREE.RingGeometry(.85,1,40),disc:new THREE.CircleGeometry(1,32),diamond:new THREE.OctahedronGeometry(.11,0)};
const palettes=[['#a84847','#283842','#885332'],['#3e7169','#283943','#a16c46'],['#6a668f','#273943','#73472f'],['#3b6a82','#293b44','#985e3b']];
const materials=new Map(),up=new THREE.Vector3(0,1,0);
let lastEnemySound=-Infinity;
function mat(color){if(!materials.has(color))materials.set(color,new THREE.MeshStandardMaterial({color,roughness:.84}));return materials.get(color);}
function deltaAngle(a,b){return THREE.MathUtils.euclideanModulo(a-b+Math.PI,Math.PI*2)-Math.PI;}
function isType(enemy,type){return enemy.type===type||enemy.config.type===type;}
function hasModifier(enemy,id){return enemy.eliteModifiers.some(modifier=>modifier.id===id);}
function damageDirection(from,to){return new THREE.Vector3(to.x-from.x,0,to.z-from.z).normalize();}
function groundAt(navigation,x,z,y){const height=navigation?.heightAt?.(x,z,y);return Number.isFinite(height)?height:y;}

export function createEnemy(scene,{x=0,y=0,z=0,seed=0,type='grunt',round=1,owner=null,roundEnemy=false,stats=null,elite=null,modifiers=[],boss=false}={}){
  const config=enemyStats(type,round,stats||{}),g=new THREE.Group(),rig=new THREE.Group();g.name=`${FACTION.name} · ${config.name}`;g.position.set(x,y,z);g.scale.setScalar(config.scale);g.add(rig);
  const eliteList=normalizeElite(elite),palette=palettes[Math.abs(Math.trunc(seed))%palettes.length],coat=palette[0],trim=palette[1],accent=eliteList[0]?.color||config.color;
  for(const modifier of eliteList)Object.assign(config.resist,modifier.resist);
  const enemy={g,rig,seed,type,config,faction:FACTION.id,health:config.hp,maxHealth:config.hp,disabled:false,dead:false,owner,roundEnemy,boss,elite:eliteList.length>0,eliteModifiers:eliteList,modifiers,velocity:new THREE.Vector3(),hitMeshes:[],healthTimer:0,hitTime:0,deathTime:0,attackTime:0,attackCooldown:1.3,navTimer:0,gait:seed,slowTime:0,slowFactor:1,stunTime:0,freezeTime:0,burnTime:0,burnTick:0,burnDamage:0,burnSource:'weapon',flying:false,hitRegion:'body',hitDirection:new THREE.Vector3(),supportClock:2.5,leapClock:2+(Math.abs(seed)%3),eliteClock:2.6,hazards:[],pendingAttack:null,ownResources:[],feet:[],stepSlope:0,lastHeading:0,turnBank:0,tripTime:0,damageBuffTime:0,speedBuffTime:0,shieldedTime:0,vulnerableTime:0,lastPosition:new THREE.Vector3(x,y,z)};
  function part(geo,color,parent,x,y,z,zone='body'){const mesh=new THREE.Mesh(geo,mat(color));mesh.position.set(x,y,z);mesh.castShadow=true;mesh.receiveShadow=true;parent.add(mesh);if(zone){mesh.userData.enemy=enemy;mesh.userData.zone=zone;enemy.hitMeshes.push(mesh);}return mesh;}
  function box(color,parent,x,y,z,sx,sy,sz,zone='body'){const p=part(geometry.box,color,parent,x,y,z,zone);p.scale.set(sx,sy,sz);return p;}
  const torso=part(geometry.torso,coat,rig,0,1.14,0);torso.scale.z=.85;
  const hips=part(geometry.torso,trim,rig,0,.78,0);hips.scale.set(.86,.35,.82);
  for(const side of [-1,1])for(const x of [-.14,.14])part(geometry.stripe,trim,rig,x,1.15,side*.293);
  // The unmistakable two-bar emblem is present on every combatant, front and back.
  for(const side of [-1,1]){
    const plate=box('#253742',rig,0,1.22,side*.306,.2,.23,.024);
    plate.rotation.z=Math.PI/4;
    for(const offset of [-.045,.045]){const bar=box('#f0ba62',rig,offset,1.22,side*.33,.04,.16,.026);bar.rotation.z=-.3;}
  }
  const collar=part(geometry.cap,trim,rig,0,1.46,0);collar.scale.set(.45,.35,.45);
  part(geometry.radio,'#24343d',rig,.34,.84,.09);part(geometry.antenna,'#303e3d',rig,.38,1.045,.09);
  const radioLight=part(geometry.badge,accent,rig,.34,.86,.15);radioLight.scale.set(.55,.2,.5);
  const headPivot=new THREE.Group();headPivot.position.set(0,1.72,0);rig.add(headPivot);
  part(geometry.head,palette[2],headPivot,0,0,0,'head');
  const nose=part(geometry.hand,palette[2],headPivot,0,-.035,.285,'head');nose.scale.set(.48,.65,.65);
  // A small geometric radio mask gives the raiders their own silhouette.
  box('#293d46',headPivot,0,-.135,.29,.34,.12,.08,'head');
  box(accent,headPivot,0,-.135,.337,.15,.025,.015,'head');
  for(const side of [-1,1]){part(geometry.eye,'#fff1c6',headPivot,side*.13,.055,.283,'head');part(geometry.eye,'#26303a',headPivot,side*.13,.055,.326,'head').scale.setScalar(.48);}
  const hair=part(geometry.head,Math.abs(seed)%4===0?'#dedbc9':'#302b27',headPivot,0,.22,-.035,'head');hair.scale.set(1.01,.42,1.02);
  const arms=[],legs=[],knees=[];
  for(const side of [-1,1]){
    const shoulder=new THREE.Group();shoulder.position.set(side*.4,1.39,0);rig.add(shoulder);arms.push(shoulder);
    part(geometry.limb,coat,shoulder,0,-.2,0,'arm');part(geometry.limb,palette[2],shoulder,0,-.53,.015,'arm');part(geometry.hand,palette[2],shoulder,0,-.73,.045,'arm');
    const hip=new THREE.Group();hip.position.set(side*.17,.78,0);rig.add(hip);legs.push(hip);
    part(geometry.limb,trim,hip,0,-.16,0,'leg');const knee=new THREE.Group();knee.position.y=-.36;hip.add(knee);knees.push(knee);
    part(geometry.limb,palette[2],knee,0,-.14,0,'leg');
    const footPivot=new THREE.Group();footPivot.position.set(0,-.34,.07);knee.add(footPivot);enemy.feet.push(footPivot);
    const foot=part(geometry.shoe,palette[2],footPivot,0,0,0,'leg');foot.scale.set(.82,.45,.85);
    part(geometry.sole,'#d3c199',footPivot,0,-.055,.02,'leg');
    for(const strapSide of [-1,1]){const strap=part(geometry.strap,coat,footPivot,strapSide*.038,.042,.07,'leg');strap.rotation.y=strapSide*.65;}
  }
  if(['tank','brute','captain'].includes(type)||boss){
    for(const side of [-1,1]){const plate=box(trim,rig,side*.46,1.4,0,.26,.23,.42,'arm');plate.rotation.z=side*.3;box(accent,rig,side*.46,1.43,.216,.12,.09,.025,'arm');}
    box('#263d47',rig,0,1.12,-.31,.5,.6,.17);box(accent,rig,0,1.12,-.407,.08,.45,.03);
  }
  if(type==='brute'){const hammer=box('#394853',arms[1],0,-.85,.1,.16,.7,.14,'arm');box(accent,hammer,0,-.45,0,2.9,.47,2.1,'arm');}
  if(type==='captain'||boss){const band=part(geometry.cap,'#e4be66',headPivot,0,.18,-.03,'head');band.scale.set(1.02,.27,1.02);for(const side of [-1,1]){const fin=box(accent,rig,side*.32,1.52,-.32,.11,.56,.15);fin.rotation.z=-side*.16;}}
  if(type==='runner'||type==='assassin'){box(trim,rig,0,1.08,-.28,.38,.43,.13);for(const side of [-1,1])box(accent,legs[side===-1?0:1],0,-.17,.105,.075,.27,.035,'leg');}
  if(type==='assassin'){const hood=part(geometry.head,trim,headPivot,0,.09,-.11,'head');hood.scale.set(1.06,1.08,.74);}
  if(type==='exploder')for(const side of [-1,1]){const tank=part(geometry.can,accent,rig,side*.2,1.19,-.33);tank.scale.set(1.1,2.2,1.1);box('#e7d9b1',rig,side*.2,1.19,-.52,.12,.04,.025);}
  if(type==='slinger'||type==='ranged')box('#445966',arms[1],0,-.66,.17,.17,.22,.47,'arm');
  if(type==='support'){const pack=box('#314c50',rig,0,1.25,-.36,.47,.64,.25);for(const side of [-1,1]){const antenna=part(geometry.antenna,accent,pack,side*.36,.7,0);antenna.scale.y=2;part(geometry.diamond,accent,rig,side*.2,1.73,-.39);}box(accent,rig,0,1.4,-.502,.12,.22,.022);}
  if(type==='shield'){
    const shield=box('#405762',rig,0,1.07,.46,.69,.99,.09,'shield');
    box('#dfbd71',shield,0,0,.6,.075,.76,.18,'shield');
    const maxHealth=config.shieldHealth||Math.round(config.hp*1.2);enemy.shield={health:maxHealth,maxHealth,mesh:shield};enemy.shieldBroken=false;
    Object.defineProperties(enemy,{shieldHealth:{get(){return this.shield.health;},set(value){this.shield.health=Math.max(0,value);}},maxShieldHealth:{get(){return this.shield.maxHealth;},set(value){this.shield.maxHealth=value;}}});
  }
  const bar=new THREE.Group();bar.position.y=2.35;
  const background=new THREE.Mesh(new THREE.PlaneGeometry(.9,.065),new THREE.MeshBasicMaterial({color:'#182528',depthTest:false}));
  const fill=new THREE.Mesh(new THREE.PlaneGeometry(.86,.035),new THREE.MeshBasicMaterial({color:boss?'#ee9b76':eliteList.length?accent:type==='captain'?'#edbd6d':'#d0dbb4',depthTest:false}));fill.position.z=.01;bar.add(background,fill);bar.visible=false;g.add(bar);
  const warningMaterial=new THREE.MeshBasicMaterial({color:'#ffc074',transparent:true,opacity:.45,depthWrite:false,side:THREE.DoubleSide});
  enemy.ownResources.push(warningMaterial);const warning=new THREE.Mesh(geometry.ring,warningMaterial);warning.rotation.x=-Math.PI/2;warning.position.y=.035;warning.visible=false;g.add(warning);enemy.warning=warning;
  if(eliteList.length){const symbol=part(geometry.diamond,accent,rig,0,2.17,0,null);symbol.scale.setScalar(1.25);enemy.eliteSymbol=symbol;}
  Object.assign(enemy,{headPivot,arms,legs,knees,healthBar:bar,barFill:fill});scene.add(g);return enemy;
}

export function animateEnemy(enemy,dt,camera,navigation){
  if(enemy.disposed)return;
  if(enemy.disabled){
    enemy.deathTime+=dt;const t=Math.min(1,enemy.deathTime/.52),ease=Math.sin(t*Math.PI/2),variant=Math.abs(enemy.seed)%3;
    enemy.rig.rotation.set(variant===0?-ease*1.35:variant===1?ease*.85:0,0,variant===2?ease*1.45:Math.sin(t*Math.PI)*.18);
    enemy.rig.position.y=-t*(variant===1?.68:.3);enemy.legs[0].rotation.x=variant===1?-ease*1.1:0;enemy.knees[0].rotation.x=ease*.8;enemy.arms.forEach((arm,index)=>arm.rotation.x=-ease*(.5+index*.25));
    enemy.g.scale.setScalar(enemy.config.scale*(enemy.deathTime>1.2?Math.max(0,1-(enemy.deathTime-1.2)/.55):1));enemy.healthBar.visible=false;enemy.warning.visible=false;return;
  }
  const speed=Math.hypot(enemy.velocity.x,enemy.velocity.z),moving=speed>.12,scale=enemy.config.scale;
  enemy.gait+=dt*(moving?speed*3.5/Math.max(.8,scale):1.6);const phase=enemy.gait,hit=enemy.hitTime>0;
  enemy.hitTime=Math.max(0,enemy.hitTime-dt);enemy.healthTimer=Math.max(0,enemy.healthTimer-dt);enemy.attackTime=Math.max(0,enemy.attackTime-dt);enemy.tripTime=Math.max(0,enemy.tripTime-dt);
  const turn=deltaAngle(enemy.g.rotation.y,enemy.lastHeading);enemy.lastHeading=enemy.g.rotation.y;
  enemy.turnBank+=(THREE.MathUtils.clamp(-turn/Math.max(dt,.01)*.035,-.2,.2)-enemy.turnBank)*Math.min(1,dt*9);
  const travelled=Math.hypot(enemy.g.position.x-enemy.lastPosition.x,enemy.g.position.z-enemy.lastPosition.z),dy=enemy.g.position.y-enemy.lastPosition.y;
  enemy.stepSlope+=(THREE.MathUtils.clamp(dy/Math.max(.03,travelled),-.8,.8)-enemy.stepSlope)*Math.min(1,dt*7);enemy.lastPosition.copy(enemy.g.position);
  const staggering=hit?Math.sin(enemy.hitTime*30)*.16:0,trip=enemy.tripTime>0?Math.sin(enemy.tripTime*13)*.11:0;
  const leap=enemy.leapTime>0?Math.sin((1-enemy.leapTime/.58)*Math.PI)*.62:0;
  enemy.rig.position.y=(moving?Math.abs(Math.sin(phase))*.037:Math.sin(phase)*.011)+leap-Math.abs(trip);
  enemy.rig.rotation.x=(moving?.11:0)+enemy.stepSlope*.18+trip-(enemy.hitRegion==='body'||enemy.hitRegion==='torso'?staggering:0);
  enemy.rig.rotation.z=enemy.turnBank+(moving?Math.sin(phase)*.025:0)+(enemy.hitRegion==='arm'?staggering:0);
  enemy.headPivot.rotation.x=enemy.hitRegion==='head'&&hit?-.24-staggering:Math.sin(phase*.5)*.025;
  const windup=enemy.pendingAttack?Math.min(1,enemy.pendingAttack.age/enemy.pendingAttack.duration):0;
  enemy.legs.forEach((leg,index)=>{
    const p=phase+index*Math.PI,stride=moving?Math.sin(p)*Math.min(.78,.42+speed*.055):0;
    leg.rotation.x=stride-(enemy.tripTime>0&&index===0?.25:0);enemy.knees[index].rotation.x=moving?Math.max(0,-Math.sin(p))*(.8+Math.max(0,enemy.stepSlope)*.5):0;
    const sx=(index?1:-1)*.2*scale,c=Math.cos(enemy.g.rotation.y),s=Math.sin(enemy.g.rotation.y),floor=groundAt(navigation,enemy.g.position.x+sx*c,enemy.g.position.z-sx*s,enemy.g.position.y);
    leg.position.y=.78+THREE.MathUtils.clamp((floor-enemy.g.position.y)/scale,-.16,.22);
    enemy.feet[index].rotation.x=-stride*.42-enemy.knees[index].rotation.x*.36;
    enemy.arms[index].rotation.x=windup?-(.65+windup*1.45):enemy.attackTime>0?-1.65:moving?-Math.sin(p)*.63:.07;
    if(enemy.type==='shield')enemy.arms[index].rotation.x=-.75;
    if(enemy.type==='slinger'||enemy.type==='ranged'||enemy.type==='support')enemy.arms[index].rotation.x=-.72+(moving?Math.sin(p)*.12:0);
  });
  if(enemy.shield&&(enemy.shield.health<=0||enemy.shieldBroken)){enemy.shieldBroken=true;enemy.shield.mesh.visible=false;}
  enemy.healthBar.visible=!enemy.boss&&(enemy.healthTimer>0||enemy.markedTime>0||enemy.elite||enemy.type==='captain');
  if(camera)enemy.healthBar.quaternion.copy(enemy.g.quaternion.clone().invert().multiply(camera.quaternion));
  if(enemy.eliteSymbol)enemy.eliteSymbol.rotation.y+=dt*1.3;
  enemy.warning.visible=!!enemy.pendingAttack&&(['brute','exploder','captain'].includes(enemy.type)||enemy.pendingAttack.kind.startsWith('elite-'));
  if(enemy.warning.visible){enemy.warning.scale.setScalar((enemy.pendingAttack.radius||enemy.config.attackRange)/scale);enemy.warning.material.opacity=.22+windup*.43;}
}

export function disposeEnemy(enemy){
  if(enemy.disposed)return;enemy.disposed=true;enemy.g.removeFromParent();
  enemy.healthBar.traverse(node=>{node.geometry?.dispose();node.material?.dispose();});
  for(const hazard of enemy.hazards||[]){hazard.mesh.removeFromParent();hazard.mesh.material.dispose();}enemy.hazards=[];
  for(const resource of enemy.ownResources)resource.dispose();
}

function hurtTarget(enemy,context,targetDog,amount,position=enemy.g.position,radius=null,frontal=false){
  const target=targetDog?context.companion?.g.position:context.player.pos;if(!target)return false;
  if(radius!==null&&(Math.hypot(target.x-position.x,target.z-position.z)>radius||Math.abs(target.y-position.y)>2.3))return false;
  if(frontal){const direction=damageDirection(position,target),forward=new THREE.Vector3(Math.sin(enemy.g.rotation.y),0,Math.cos(enemy.g.rotation.y));if(direction.dot(forward)<.1)return false;}
  if(!context.navigation.clearLine(position,target,.1))return false;
  const damage=amount*(enemy.damageBuffTime>0?1.16:1);
  if(targetDog)context.hurtDog?.(damage);else context.hurtPlayer?.(damage,damageDirection(position,target));
  if(hasModifier(enemy,'vampiric'))enemy.health=Math.min(enemy.maxHealth,enemy.health+damage*.4);
  if(!targetDog&&hasModifier(enemy,'frost')){context.player.slowTime=Math.max(context.player.slowTime||0,1.2);context.player.slowFactor=Math.min(context.player.slowFactor||1,.7);}
  context.emit?.('enemy-hit',{enemy,effect:enemy.eliteModifiers[0]?.effect||'kinetic',target:targetDog?'dog':'player',damage});return true;
}
function explode(enemy,context,radius,amount){
  const point=enemy.g.position.clone().addScaledVector(up,.4);
  context.combat?.effects?.nova?.(point,'#f0a56f',radius);context.combat?.effects?.burst?.(point,'#ffd28a',9,2);
  context.combat?.effects?.sound?.('crash');context.emit?.('enemy-explosion',{enemy,point,radius});
  hurtTarget(enemy,context,false,amount,enemy.g.position,radius);
  if(context.companion?.health>0)hurtTarget(enemy,context,true,amount*.6,enemy.g.position,radius);
}
function beginAttack(enemy,kind,targetDog,target,duration,radius){enemy.pendingAttack={kind,targetDog,target:target.clone(),age:0,duration,radius};enemy.velocity.multiplyScalar(.2);}
function eliteAttack(enemy,context,attack){
  const point=enemy.g.position.clone(),kind=attack.kind.slice(6),color=enemy.eliteModifiers.find(m=>m.id===kind)?.color||'#eec170';
  context.combat?.effects?.nova?.(point.clone().addScaledVector(up,.12),color,attack.radius);
  hurtTarget(enemy,context,false,enemy.config.damage*.8,point,attack.radius);
  if(context.companion?.health>0)hurtTarget(enemy,context,true,enemy.config.damage*.5,point,attack.radius);
  if(kind==='fire'&&enemy.hazards.length<2){
    const material=new THREE.MeshBasicMaterial({color,side:THREE.DoubleSide,transparent:true,opacity:.34,depthWrite:false}),mesh=new THREE.Mesh(geometry.ring,material);mesh.rotation.x=-Math.PI/2;mesh.scale.setScalar(2.3);mesh.position.copy(point).y+=.05;enemy.g.parent?.add(mesh);
    enemy.hazards.push({mesh,point,age:0,tick:.65,duration:2.1,radius:2.3});
  }
  enemy.eliteClock=6;context.emit?.('enemy-elite-attack',{enemy,kind,point,radius:attack.radius});
}
function tickHazards(enemy,context){
  for(let index=enemy.hazards.length-1;index>=0;index--){const hazard=enemy.hazards[index];hazard.age+=context.dt;hazard.tick-=context.dt;hazard.mesh.material.opacity=.28+Math.sin(hazard.age*8)*.09;
    if(hazard.age>=hazard.duration){hazard.mesh.removeFromParent();hazard.mesh.material.dispose();enemy.hazards.splice(index,1);continue;}
    if(hazard.tick<=0){hazard.tick=.65;hurtTarget(enemy,context,false,enemy.config.damage*.28,hazard.point,hazard.radius);context.combat?.effects?.burst?.(hazard.point.clone().addScaledVector(up,.12),'#ffc187',2,.3);}
  }
}

export function updateEnemyAI(enemy,context){
  const {dt,player,companion,navigation,peers=[],camera,time=0,combat}=context;
  if(enemy.disposed||enemy.bossManaged)return;
  tickHazards(enemy,context);
  if(enemy.disabled){
    if(hasModifier(enemy,'volatile')&&!enemy.deathBurst&&enemy.deathTime+dt>=.65){enemy.deathBurst=true;explode(enemy,context,2.7,enemy.config.damage*.7);}
    animateEnemy(enemy,dt,camera,navigation);return;
  }
  for(const key of ['attackCooldown','slowTime','stunTime','freezeTime','leapTime','damageBuffTime','speedBuffTime','shieldedTime','vulnerableTime','tauntTime','markedTime','eliteClock'])enemy[key]=Math.max(0,(enemy[key]||0)-dt);
  const position=enemy.g.position,distance=position.distanceTo(player.pos),taunted=enemy.tauntTime>0&&enemy.tauntTarget?.health>0,targetDog=!!(taunted||companion&&companion.health>0&&enemy.seed%3===0&&companion.g.position.distanceTo(position)<5&&distance>2),target=taunted?enemy.tauntTarget.g.position:targetDog?companion.g.position:player.pos,targetDistance=Math.hypot(target.x-position.x,target.z-position.z);
  if(!enemy.roundEnemy&&distance>20){enemy.velocity.multiplyScalar(Math.exp(-dt*8));animateEnemy(enemy,dt,camera,navigation);return;}
  if(enemy.hitTime>.1&&(enemy.hitRegion==='leg'||enemy.lastHit?.zone==='leg')){enemy.tripTime=Math.max(enemy.tripTime,.24);enemy.pendingAttack=null;}
  if(enemy.freezeTime>0||enemy.stunTime>0){enemy.pendingAttack=null;enemy.velocity.multiplyScalar(Math.exp(-dt*15));animateEnemy(enemy,dt,camera,navigation);return;}
  if(enemy.pendingAttack){
    const attack=enemy.pendingAttack;attack.age+=dt;enemy.velocity.multiplyScalar(Math.exp(-dt*12));
    const facing=Math.atan2(attack.target.x-position.x,attack.target.z-position.z);enemy.g.rotation.y+=deltaAngle(facing,enemy.g.rotation.y)*Math.min(1,dt*5);
    if(attack.age>=attack.duration){
      enemy.pendingAttack=null;enemy.attackTime=.32;enemy.attackCooldown=enemy.config.attackCooldown/Math.max(.6,(enemy.config.aggression||1)*(context.aggression||1))*(hasModifier(enemy,'frenzied')?.7:1);
      if(attack.kind==='ranged'){context.fireRanged?.(enemy,attack.target);context.emit?.('enemy-ranged',{enemy});}
      else if(attack.kind.startsWith('elite-'))eliteAttack(enemy,context,attack);
      else if(attack.kind==='explode'){
        explode(enemy,context,enemy.config.explosionRadius,enemy.config.damage);
        if(combat?.damage)combat.damage(enemy,enemy.health+1,{source:'self',effect:'explosive',bypassShield:true});else {enemy.disabled=enemy.dead=true;enemy.health=0;context.emit?.('enemy-self-kill',{enemy});}
      }else{
        hurtTarget(enemy,context,attack.targetDog,enemy.config.damage,position,attack.radius,!['brute','captain'].includes(enemy.type));
        if(['brute','captain'].includes(enemy.type)){combat?.effects?.nova?.(position.clone().addScaledVector(up,.1),'#f1bc8b',attack.radius);combat?.effects?.sound?.('impact');}
      }
    }
    animateEnemy(enemy,dt,camera,navigation);return;
  }
  const elementalElite=enemy.eliteModifiers.find(modifier=>['fire','shock','frost'].includes(modifier.id));
  if(elementalElite&&enemy.eliteClock<=0&&targetDistance<4.8&&Math.abs(position.y-target.y)<1.8&&navigation.clearLine(position,target,.1)){
    enemy.warning.material.color.set(elementalElite.color);beginAttack(enemy,`elite-${elementalElite.id}`,targetDog,target,.9,elementalElite.id==='shock'?4.5:3.3);animateEnemy(enemy,dt,camera,navigation);return;
  }
  // A support pulse has a cooldown, a maximum number of recipients and cannot heal itself.
  if(isType(enemy,'support')){
    enemy.supportClock-=dt;
    if(enemy.supportClock<=0){
      enemy.supportClock=enemy.config.healCooldown;let healed=0;
      for(const ally of peers){if(ally===enemy||ally.disabled||ally.boss||healed>=5||ally.g.position.distanceTo(position)>enemy.config.healRadius||!navigation.clearLine(position,ally.g.position,.1))continue;
        ally.health=Math.min(ally.maxHealth,ally.health+Math.max(3,ally.maxHealth*.07));ally.damageBuffTime=3;ally.speedBuffTime=3;ally.healthTimer=Math.max(ally.healthTimer,.65);const ratio=ally.health/ally.maxHealth;ally.barFill.scale.x=ratio;ally.barFill.position.x=-(1-ratio)*.43;healed++;
      }
      if(healed){combat?.effects?.nova?.(position.clone().addScaledVector(up,.18),'#9cd1b4',2.5);context.emit?.('enemy-support',{enemy,count:healed});}
    }
  }
  const desired=target.clone();
  // Local separation respects height; actors on an upper roof do not repel those below.
  for(const other of peers){if(other===enemy||other.disabled||Math.abs(other.g.position.y-position.y)>1.7)continue;const dx=position.x-other.g.position.x,dz=position.z-other.g.position.z,d=dx*dx+dz*dz;if(d>.001&&d<1.3){desired.x+=dx/d*.55;desired.z+=dz/d*.55;}}
  if((isType(enemy,'zigzag')||isType(enemy,'assassin'))&&targetDistance>4){const dx=target.x-position.x,dz=target.z-position.z,l=Math.hypot(dx,dz)||1;desired.x+=dz/l*Math.sin(time*2.4+enemy.seed)*1.6;desired.z-=dx/l*Math.sin(time*2.4+enemy.seed)*1.6;}
  const ranged=isType(enemy,'ranged')||isType(enemy,'support'),attackRange=enemy.config.attackRange*(ranged?1:enemy.config.scale),clearAttack=ranged&&combat?.hitWorld?combat.hitWorld.lineOfSight(position.clone().addScaledVector(up,enemy.config.scale*1.3),target.clone().addScaledVector(up,.7)):navigation.clearLine(position,target,.15);
  let speed=enemy.config.speed;
  if(isType(enemy,'berserker'))speed*=1+(1-enemy.health/enemy.maxHealth)*.65;
  if(enemy.speedBuffTime>0)speed*=1.1;if(hasModifier(enemy,'frenzied'))speed*=1.22;
  speed=Math.min(enemy.config.maxSpeed,speed)*(enemy.slowTime>0?enemy.slowFactor:1)*(enemy.tripTime>0?.45:1);
  if(isType(enemy,'assassin')){enemy.leapClock-=dt;if(enemy.leapClock<=0&&targetDistance>3&&targetDistance<8&&clearAttack){enemy.leapClock=enemy.config.leapCooldown;enemy.leapTime=.58;context.emit?.('enemy-leap',{enemy});}if(enemy.leapTime>0)speed=Math.min(enemy.config.maxSpeed,speed*1.2);}
  if(ranged&&targetDistance<4){const away=damageDirection(target,position);desired.copy(position).addScaledVector(away,3);navigation.move(enemy,desired,speed*.75,dt,.4*enemy.config.scale);}
  else if(targetDistance>attackRange*.8||!clearAttack)navigation.move(enemy,desired,speed,dt,.4*enemy.config.scale);
  else {enemy.velocity.multiplyScalar(Math.exp(-dt*12));const face=Math.atan2(target.x-position.x,target.z-position.z);enemy.g.rotation.y+=deltaAngle(face,enemy.g.rotation.y)*Math.min(1,dt*6);}
  if(targetDistance<attackRange&&Math.abs(position.y-target.y)<2.2&&enemy.attackCooldown<=0&&clearAttack){
    const explosive=isType(enemy,'exploder'),windup=enemy.config.windup||(ranged?.32:['brute','captain'].includes(enemy.type)?.7:.18);
    beginAttack(enemy,explosive?'explode':ranged?'ranged':'melee',targetDog,target,windup,explosive?enemy.config.explosionRadius:attackRange);
    if(targetDistance<12&&(time-lastEnemySound>.38||time<lastEnemySound)){combat?.effects?.sound?.(`enemy-${enemy.type}`);lastEnemySound=time;}
    context.emit?.('enemy-windup',{enemy,kind:enemy.pendingAttack.kind,duration:windup});
  }
  animateEnemy(enemy,dt,camera,navigation);
}
