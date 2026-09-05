import * as THREE from 'three';
import {enemyStats} from './config.js';

// Original, low-poly "Bando da Lata" rigs. Their visible body parts ARE their shot surfaces.
const geometry={head:new THREE.SphereGeometry(.32,10,8),torso:new THREE.CylinderGeometry(.35,.29,.68,8),limb:new THREE.CapsuleGeometry(.11,.27,3,6),shoe:new THREE.BoxGeometry(.23,.17,.36),eye:new THREE.SphereGeometry(.055,6,5),hand:new THREE.SphereGeometry(.13,7,6),cap:new THREE.CylinderGeometry(.34,.34,.15,10),can:new THREE.CylinderGeometry(.16,.16,.35,8),sole:new THREE.BoxGeometry(.23,.055,.38),stripe:new THREE.BoxGeometry(.035,.53,.025),radio:new THREE.BoxGeometry(.14,.23,.1),antenna:new THREE.CylinderGeometry(.008,.008,.23,5),strap:new THREE.BoxGeometry(.1,.025,.035),badge:new THREE.BoxGeometry(.07,.09,.02)};
// Fictional football kits, varied brown skin tones and occasional platinum fades.
const palettes=[['#b65048','#253d48','#885332'],['#487c68','#ded5ad','#a16c46'],['#ece5c8','#294b53','#73472f'],['#4c799b','#d9ceae','#985e3b']];
const materials=new Map();
function mat(color){if(!materials.has(color))materials.set(color,new THREE.MeshStandardMaterial({color,roughness:.85}));return materials.get(color);}

export function createEnemy(scene,{x,z,seed=0,type='grunt',round=1,owner=null,roundEnemy=false}){
  const config=enemyStats(type,round),g=new THREE.Group(),rig=new THREE.Group();g.position.set(x,0,z);g.scale.setScalar(config.scale);g.add(rig);
  const palette=palettes[Math.abs(seed)%palettes.length],coat=palette[0],trim=palette[1];
  const enemy={g,rig,seed,type,config,health:config.hp,maxHealth:config.hp,disabled:false,dead:false,owner,roundEnemy,velocity:new THREE.Vector3(),hitMeshes:[],healthTimer:0,hitTime:0,deathTime:0,attackTime:0,attackCooldown:1.3,navTimer:0,gait:seed,slowTime:0,slowFactor:1,stunTime:0,burnTime:0,burnTick:0,burnDamage:0,burnSource:'weapon',flying:false};
  function part(geo,color,parent,x,y,z,zone='body'){const mesh=new THREE.Mesh(geo,mat(color));mesh.position.set(x,y,z);mesh.castShadow=true;mesh.receiveShadow=true;parent.add(mesh);if(zone){mesh.userData.enemy=enemy;mesh.userData.zone=zone;enemy.hitMeshes.push(mesh);}return mesh;}
  const torso=part(geometry.torso,coat,rig,0,1.14,0);torso.scale.z=.85;
  const hips=part(geometry.torso,palette[1],rig,0,.78,0);hips.scale.set(.86,.35,.82);
  for(const side of [-1,1])for(const x of [-.14,0,.14])part(geometry.stripe,trim,rig,x,1.15,side*.293);
  part(geometry.badge,'#e4c674',rig,-.21,1.35,.278);
  const collar=part(geometry.cap,trim,rig,0,1.46,0);collar.scale.set(.45,.35,.45);
  part(geometry.radio,'#293738',rig,.34,.84,.09);part(geometry.antenna,'#303e3d',rig,.38,1.045,.09);
  const radioLight=part(geometry.badge,'#bcd4a0',rig,.34,.86,.15);radioLight.scale.set(.55,.2,.5);
  const headPivot=new THREE.Group();headPivot.position.set(0,1.72,0);rig.add(headPivot);
  part(geometry.head,palette[2],headPivot,0,0,0,'head');
  const nose=part(geometry.hand,palette[2],headPivot,0,-.035,.285,'head');nose.scale.set(.48,.65,.65);
  const mouth=part(geometry.strap,'#513b2e',headPivot,0,-.16,.282,'head');mouth.scale.set(1,.7,.5);
  for(const side of [-1,1]){part(geometry.eye,'#fff1c6',headPivot,side*.13,.055,.283,'head');part(geometry.eye,'#26303a',headPivot,side*.13,.055,.326,'head').scale.setScalar(.48);}
  const hair=part(geometry.head,Math.abs(seed)%4===0?'#dedbc9':'#302b27',headPivot,0,.22,-.035,'head');hair.scale.set(1.01,.42,1.02);
  if(type==='tank'||type==='captain')for(const side of [-1,1]){const sleeve=part(geometry.can,coat,rig,side*.43,1.34,0);sleeve.scale.set(1.15,.8,1);sleeve.rotation.z=side*.6;}
  if(type==='captain'){const band=part(geometry.cap,'#e4be66',headPivot,0,.18,-.03,'head');band.scale.set(1.02,.27,1.02);}
  const arms=[],legs=[],knees=[];
  for(const side of [-1,1]){
    const shoulder=new THREE.Group();shoulder.position.set(side*.4,1.39,0);rig.add(shoulder);arms.push(shoulder);
    part(geometry.limb,coat,shoulder,0,-.2,0);part(geometry.limb,palette[2],shoulder,0,-.53,.015);part(geometry.hand,palette[2],shoulder,0,-.73,.045);
    const hip=new THREE.Group();hip.position.set(side*.17,.78,0);rig.add(hip);legs.push(hip);
    part(geometry.limb,palette[1],hip,0,-.16,0);const knee=new THREE.Group();knee.position.y=-.36;hip.add(knee);knees.push(knee);
    part(geometry.limb,palette[2],knee,0,-.14,0);
    const foot=part(geometry.shoe,palette[2],knee,0,-.335,.07);foot.scale.set(.82,.45,.85);
    part(geometry.sole,'#d3c199',knee,0,-.395,.09);
    for(const side of [-1,1]){const strap=part(geometry.strap,coat,knee,side*.038,-.293,.14);strap.rotation.y=side*.65;}
  }
  const bar=new THREE.Group();bar.position.y=2.35;
  const background=new THREE.Mesh(new THREE.PlaneGeometry(.9,.065),new THREE.MeshBasicMaterial({color:'#182528',depthTest:false}));
  const fill=new THREE.Mesh(new THREE.PlaneGeometry(.86,.035),new THREE.MeshBasicMaterial({color:config.type==='miniboss'?'#edbd6d':'#d0dbb4',depthTest:false}));fill.position.z=.01;bar.add(background,fill);bar.visible=false;g.add(bar);
  Object.assign(enemy,{headPivot,arms,legs,knees,healthBar:bar,barFill:fill});scene.add(g);return enemy;
}

export function animateEnemy(enemy,dt,camera){
  if(enemy.disabled){enemy.deathTime+=dt;const t=Math.min(1,enemy.deathTime/.45);enemy.rig.rotation.z=Math.sin(t*Math.PI/2)*1.45;enemy.rig.position.y=-t*.42;enemy.g.scale.setScalar(enemy.config.scale*(enemy.deathTime>1.2?Math.max(0,1-(enemy.deathTime-1.2)/.5):1));enemy.healthBar.visible=false;return;}
  const speed=enemy.velocity.length(),moving=speed>.12;
  enemy.gait+=dt*(moving?speed*3.5:2);const phase=enemy.gait,hit=enemy.hitTime>0;
  enemy.hitTime=Math.max(0,enemy.hitTime-dt);enemy.healthTimer=Math.max(0,enemy.healthTimer-dt);enemy.attackTime=Math.max(0,enemy.attackTime-dt);
  enemy.rig.position.y=moving?Math.abs(Math.sin(phase))*.045:Math.sin(phase)*.013;
  enemy.rig.rotation.x=(moving?.12:0)-(hit?Math.sin(enemy.hitTime*32)*.18:0);
  enemy.rig.rotation.z=moving?Math.sin(phase)*.035:0;
  enemy.headPivot.rotation.x=hit?-.15:Math.sin(phase*.5)*.025;
  enemy.legs.forEach((leg,index)=>{const p=phase+index*Math.PI;leg.rotation.x=moving?Math.sin(p)*.65:0;enemy.knees[index].rotation.x=moving?Math.max(0,-Math.sin(p))*.9:0;enemy.arms[index].rotation.x=enemy.attackTime>0?-1.1: moving?-Math.sin(p)*.65:.07;});
  enemy.healthBar.visible=enemy.healthTimer>0||enemy.type==='captain';
  enemy.healthBar.quaternion.copy(enemy.g.quaternion.clone().invert().multiply(camera.quaternion));
}

export function disposeEnemy(enemy){
  enemy.g.removeFromParent();
  // Body geometries/materials are shared. Only the per-enemy bar owns GPU resources.
  enemy.healthBar.traverse(node=>{node.geometry?.dispose();node.material?.dispose();});
}

export function updateEnemyAI(enemy,{dt,player,companion,navigation,peers,hurtPlayer,hurtDog,fireRanged,camera,time}){
  if(enemy.disabled){animateEnemy(enemy,dt,camera);return;}
  enemy.attackCooldown=Math.max(0,enemy.attackCooldown-dt);enemy.slowTime=Math.max(0,enemy.slowTime-dt);enemy.stunTime=Math.max(0,enemy.stunTime-dt);
  const position=enemy.g.position,distance=position.distanceTo(player.pos),targetDog=companion&&companion.health>0&&enemy.seed%3===0&&companion.g.position.distanceTo(position)<5&&distance>2;
  const target=targetDog?companion.g.position:player.pos;
  const targetDistance=Math.hypot(target.x-position.x,target.z-position.z);
  if(!enemy.roundEnemy&&distance>18){enemy.velocity.multiplyScalar(.8);animateEnemy(enemy,dt,camera);return;}
  const desired=target.clone();
  // Separation makes the front of a horde readable and prevents coincident bodies.
  for(const other of peers){if(other===enemy||other.disabled)continue;const dx=position.x-other.g.position.x,dz=position.z-other.g.position.z,d=dx*dx+dz*dz;if(d>.001&&d<1.3){desired.x+=dx/d*.6;desired.z+=dz/d*.6;}}
  if(enemy.config.type==='zigzag'&&targetDistance>4){const dx=target.x-position.x,dz=target.z-position.z,l=Math.hypot(dx,dz)||1;desired.x+=dz/l*Math.sin(time*2.4+enemy.seed)*1.8;desired.z-=dx/l*Math.sin(time*2.4+enemy.seed)*1.8;}
  const ranged=enemy.config.type==='ranged',attackRange=ranged?13:1.3*enemy.config.scale;
  const clearAttack=navigation.clearLine(position,target,.15);
  if(enemy.stunTime<=0&&(targetDistance>attackRange*.85||!clearAttack)){navigation.move(enemy,desired,enemy.config.speed*(enemy.slowTime>0?enemy.slowFactor:1),dt,.4*enemy.config.scale);}else enemy.velocity.multiplyScalar(Math.exp(-dt*12));
  if(enemy.stunTime<=0&&targetDistance<attackRange&&Math.abs(position.y-target.y)<2.2&&enemy.attackCooldown<=0&&clearAttack){
    enemy.attackCooldown=ranged?2:1.2;enemy.attackTime=.23;
    if(ranged)fireRanged(enemy);else if(targetDog)hurtDog(enemy.config.damage);else hurtPlayer(enemy.config.damage,new THREE.Vector3(target.x-position.x,0,target.z-position.z).normalize());
  }
  animateEnemy(enemy,dt,camera);
}
