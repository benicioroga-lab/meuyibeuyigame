import * as THREE from 'three';
import {DOG_CONFIG,DOG_UPGRADES,dogStats} from './config.js';

export class DogTraining {
  constructor(){this.levels=Object.fromEntries(Object.keys(DOG_UPGRADES).map(id=>[id,0]));}
  stats(){return dogStats(this.levels);}
  cost(id){const config=DOG_UPGRADES[id];return !config||this.levels[id]>=config.max?null:Math.round(config.baseCost*Math.pow(config.costScale,this.levels[id]));}
  unlock(id){const config=DOG_UPGRADES[id];return config?config.unlockRound+(id==='element'?this.levels[id]*4:0):Infinity;}
  buy(id,wallet,round){const cost=this.cost(id);if(cost===null||round<this.unlock(id)||wallet.coins<cost)return false;wallet.coins-=cost;this.levels[id]++;return true;}
  next(id){if(this.cost(id)===null)return null;this.levels[id]++;const next=this.stats();this.levels[id]--;return next;}
}

export class DogSystem {
  constructor({scene,hero,player,enemies,navigation,combat,toast}){
    Object.assign(this,{scene,hero,player,enemies,navigation,combat,toast});this.training=new DogTraining();this.followOnly=false;this.gait=0;this.trailTime=0;this.visualTier=-1;this.health=DOG_CONFIG.health;this.downed=0;this.attackCooldown=.5;this.attackPose=0;this.hurtCooldown=0;this.navTimer=0;this.seed=5;this.velocity=new THREE.Vector3();this.status='SEGUINDO';this.kills=0;
    this.geometries=[];this.materials=[];this.g=new THREE.Group();this.g.position.copy(player.pos).add(new THREE.Vector3(-1.8,0,-1));scene.add(this.g);
    const material=(color,glow=false)=>{const m=new THREE.MeshStandardMaterial({color,roughness:.75,emissive:glow?color:'#000000',emissiveIntensity:glow?.5:0});this.materials.push(m);return m;};
    const fur=material('#b7794a'),dark=material('#644330'),black=material('#263039'),cream=material('#d7a974');this.accent=material('#efbb66',true);
    const mesh=(geometry,mat,x,y,z,parent=this.g)=>{this.geometries.push(geometry);const m=new THREE.Mesh(geometry,mat);m.position.set(x,y,z);m.castShadow=true;parent.add(m);return m;};
    this.body=mesh(new THREE.CapsuleGeometry(.24,.7,4,9),fur,0,.4,0);this.body.rotation.x=Math.PI/2;
    this.head=new THREE.Group();this.head.position.set(0,.57,.6);this.g.add(this.head);
    mesh(new THREE.SphereGeometry(.255,10,8),fur,0,0,0,this.head);mesh(new THREE.SphereGeometry(.17,8,6),cream,0,-.06,.23,this.head).scale.set(1,.7,1.35);mesh(new THREE.SphereGeometry(.06,7,5),black,0,-.005,.43,this.head);
    for(const side of [-1,1]){mesh(new THREE.SphereGeometry(.033,6,4),black,side*.13,.06,.22,this.head);const ear=mesh(new THREE.CapsuleGeometry(.085,.24,3,7),dark,side*.245,-.12,-.03,this.head);ear.rotation.z=side*.12;}
    this.legs=[];for(const x of [-.17,.17])for(const z of [-.39,.39]){const leg=new THREE.Group();leg.position.set(x,.3,z);this.g.add(leg);mesh(new THREE.CapsuleGeometry(.065,.18,3,6),fur,0,-.14,0,leg);this.legs.push(leg);}
    this.tail=mesh(new THREE.CapsuleGeometry(.04,.3,3,6),dark,0,.54,-.64);this.tail.rotation.x=-.5;
    this.collar=mesh(new THREE.TorusGeometry(.235,.035,5,14),this.accent,0,.52,.49);this.collar.visible=false;
    this.aura=mesh(new THREE.TorusGeometry(.67,.016,4,24),this.accent,0,.04,0);this.aura.rotation.x=Math.PI/2;this.aura.visible=false;this.aura.castShadow=false;
    this.heroTrim=new THREE.Group();hero.add(this.heroTrim);mesh(new THREE.TorusGeometry(.34,.035,5,18),this.accent,0,.82,-.47,this.heroTrim);this.heroTrim.visible=false;
  }
  upgrade(id,wallet,round){const cost=this.training.cost(id),before=this.training.stats();if(!this.training.buy(id,wallet,round))return false;const after=this.training.stats();this.health=Math.min(after.health,this.health+after.health-before.health);this.combat.game.reward(-cost);this.combat.effects.sound('purchase');this.updateVisuals();this.toast(`${DOG_UPGRADES[id].name} — Faro evoluiu!`);return true;}
  command(){this.followOnly=!this.followOnly;this.path=null;this.toast(this.followOnly?'Faro, junto! Ele protege sua retaguarda.':'Faro, pode caçar!');}
  heal(wallet,cost=40){if(this.health>=this.training.stats().health||wallet.coins<cost)return false;wallet.coins-=cost;this.health=this.training.stats().health;this.downed=0;this.g.rotation.z=0;this.combat.game.reward(-cost);this.toast('Faro recuperado e pronto para a próxima.');return true;}
  hurt(amount){if(this.downed>0||this.hurtCooldown>0)return;this.health=Math.max(0,this.health-Math.round(amount*(1-this.training.stats().resistance)));this.hurtCooldown=.7;if(this.health<=0){this.downed=DOG_CONFIG.reviveTime;this.status='DESCANSANDO';this.toast('Faro precisa respirar. Ele volta em 9 segundos.');}this.updateHUD();}
  updateVisuals(){
    const stats=this.training.stats(),tier=stats.element>=3?3:stats.element>=2||stats.level>=9?2:stats.level>=3?1:0;if(tier===this.visualTier)return;
    this.visualTier=tier;this.collar.visible=tier>=1;this.heroTrim.visible=tier>=1;this.aura.visible=tier>=2;
    const color=tier>=3?'#c1adff':tier>=2?'#9bdeec':'#efbb66';this.accent.color.set(color);this.accent.emissive.set(color);this.accent.emissiveIntensity=tier>=2?.7:.1;
  }
  update(dt,time){
    const stats=this.training.stats();this.updateVisuals();this.attackCooldown=Math.max(0,this.attackCooldown-dt);this.attackPose=Math.max(0,this.attackPose-dt);this.hurtCooldown=Math.max(0,this.hurtCooldown-dt);
    if(this.downed>0){this.downed-=dt;this.g.rotation.z=THREE.MathUtils.lerp(this.g.rotation.z,1.3,Math.min(1,dt*8));if(this.downed<=0){this.health=Math.ceil(stats.health*.55);this.g.rotation.z=0;const home=this.player.pos.clone().add(new THREE.Vector3(-1.5,0,-1));home.y=0;this.navigation.freePosition(home,.3);this.g.position.copy(home);this.path=null;this.toast('Faro voltou. Bom cachorro!');}this.updateHUD();return;}
    const homeDistance=this.g.position.distanceTo(this.player.pos);
    if(homeDistance>32){const home=this.player.pos.clone().add(new THREE.Vector3(-2,0,-1));home.y=0;this.navigation.freePosition(home,.3);this.g.position.copy(home);this.path=null;}
    const candidates=this.followOnly?[]:this.enemies.filter(e=>!e.disabled&&e.g.position.distanceTo(this.player.pos)<stats.leash&&e.g.position.distanceTo(this.g.position)<12);
    candidates.sort((a,b)=>a.g.position.distanceToSquared(this.g.position)-b.g.position.distanceToSquared(this.g.position));const target=candidates[0];
    let speed=0;
    if(target){
      this.status='CAÇANDO';const distance=target.g.position.distanceTo(this.g.position);
      if(distance>stats.attackRange+target.config.scale*.2||!this.navigation.clearLine(this.g.position,target.g.position,.1))speed=this.navigation.move(this,target.g.position,stats.speed,dt,.25);
      else if(this.attackCooldown<=0&&this.navigation.clearLine(this.g.position,target.g.position,.1)){
        this.status='ATACANDO';this.attackCooldown=stats.attackCooldown;this.attackPose=.25;this.combat.effects.sound('dog');
        const targets=candidates.filter(e=>e.g.position.distanceTo(this.g.position)<stats.attackRange+e.config.scale*.2&&this.navigation.clearLine(this.g.position,e.g.position,.1)).slice(0,stats.targets);
        for(const enemy of targets){const critical=Math.random()<stats.criticalChance,execution=stats.element>=3&&enemy.health/enemy.maxHealth<.16;const amount=execution?enemy.health:stats.damage*(critical?1.7:1);this.combat.damage(enemy,amount,{source:'dog',critical,effect:stats.element?'chain':'kinetic'});this.combat.effects.burst(enemy.g.position.clone().add(new THREE.Vector3(0,.7,0)),stats.element?'#b1e2ef':'#e6c69d',4,.8);if(stats.element){enemy.stunTime=Math.max(enemy.stunTime,.22);this.combat.chain(enemy,stats.damage*.4,stats.element>=3?2:1,4,'dog');}if(stats.element>=2)this.combat.applyStatus(enemy,{effect:'frost',slow:.6,slowDuration:1.8});}
        if(stats.element>=3)this.combat.effects.nova(this.g.position,'#c5aeff',1.4);
      }
    }else{
      this.status=this.followOnly?'JUNTO':'SEGUINDO';const offset=new THREE.Vector3(Math.cos(this.player.cameraYaw)*1.6,0,-Math.sin(this.player.cameraYaw)*1.6);const home=this.player.pos.clone().add(offset);home.y=0;
      if(this.g.position.distanceTo(home)>1)speed=this.navigation.move(this,home,stats.speed,dt,.25);else this.velocity.multiplyScalar(Math.exp(-dt*8));
      this.health=Math.min(stats.health,this.health+dt*(this.followOnly?2:1));
    }
    this.gait+=dt*(speed> .2?speed*5:3);this.legs.forEach((leg,i)=>leg.rotation.x=speed>.2?Math.sin(this.gait+(i===0||i===3?0:Math.PI))*.6:0);this.tail.rotation.z=Math.sin(time*8)*.35;
    this.head.rotation.x=this.attackPose>0?-Math.sin(this.attackPose*12)*.25:0;this.body.position.y=.4+(speed>.2?Math.abs(Math.sin(this.gait))*.018:0);
    if(this.aura.visible)this.aura.rotation.z=time*.6;
    this.trailTime-=dt;if(this.visualTier>=3&&speed>3&&this.trailTime<=0){this.trailTime=.22;this.combat.effects.burst(this.g.position,'#c1adff',1,.12);}
    this.updateHUD();
  }
  updateHUD(){const stats=this.training.stats();const set=(id,value)=>{const el=document.getElementById(id);if(el&&el.textContent!==String(value))el.textContent=value;};set('dogStatus',this.downed>0?`VOLTA EM ${Math.ceil(this.downed)}s`:this.status);set('dogLevel',`NV ${stats.level}`);set('dogHealth',`${Math.ceil(this.health)} / ${stats.health}`);const fill=document.getElementById('dogHealthFill');if(fill)fill.style.width=`${this.health/stats.health*100}%`;}
  dispose(){this.g.removeFromParent();this.heroTrim.removeFromParent();this.geometries.forEach(g=>g.dispose());this.materials.forEach(m=>m.dispose());}
}
