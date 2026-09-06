import * as THREE from 'three';
import {DOG_CONFIG,DOG_UPGRADES,dogStats} from './config.js';

export const DOG_TALENTS=Object.freeze({
  scout:{name:'Busca-munição',description:'Faro busca caixas de munição e volta ao seu lado.',branch:'support',max:2,baseCost:160,costScale:1.8,unlockRound:1,stat:'ammoRange',label:'Busca de munição',unit:'m'},
  courier:{name:'Entrega expressa',description:'Faro recolhe dinheiro e petiscos próximos.',branch:'support',max:3,baseCost:120,costScale:1.65,unlockRound:1,stat:'coinRange',label:'Busca de dinheiro',unit:'m'},
  tracker:{name:'Olho nos especiais',description:'Marca elites e inimigos perigosos, revelando suas barras de vida.',branch:'support',max:2,baseCost:200,costScale:1.8,unlockRound:3,stat:'markRange',label:'Alcance de marcação',unit:'m'},
  rescue:{name:'Melhor amigo',description:'Faro pode levantar você uma vez por partida. Ele precisa chegar perto e sobreviver ao resgate.',branch:'survival',max:2,baseCost:420,costScale:2,unlockRound:3,stat:'reviveHealth',label:'Vida ao levantar',unit:'%'},
  barrier:{name:'Coleira de proteção',description:'Quando sua vida cai abaixo de 65%, Faro gera um escudo temporário.',branch:'survival',max:2,baseCost:260,costScale:1.9,unlockRound:2,stat:'shieldAmount',label:'Escudo por ativação',unit:'HP'},
  decoy:{name:'Latido de guarda',description:'Atrai inimigos próximos para Faro por um instante quando você está em perigo.',branch:'survival',max:2,baseCost:220,costScale:1.8,unlockRound:2,stat:'tauntRadius',label:'Alcance do desvio',unit:'m'},
});
export function dogTalentStats(talents={}){
  const level=id=>Math.max(0,Math.min(DOG_TALENTS[id].max,Number(talents[id])||0));
  return {ammoRange:level('scout')?4+level('scout')*4:0,coinRange:level('courier')?2+level('courier')*4:0,markRange:level('tracker')?6+level('tracker')*6:0,reviveTime:level('rescue')?3.6-level('rescue')*.6:0,reviveHealth:level('rescue')?.2+level('rescue')*.1:0,shieldAmount:level('barrier')?8+level('barrier')*8:0,shieldCooldown:35-(level('barrier')-1)*8,tauntRadius:level('decoy')?5+level('decoy')*2:0,tauntCooldown:22-(level('decoy')-1)*4,level:Object.keys(DOG_TALENTS).reduce((sum,id)=>sum+level(id),0)};
}
export class DogTraining {
  constructor({healthMultiplier=1}={}){this.levels=Object.fromEntries(Object.keys(DOG_UPGRADES).map(id=>[id,0]));this.talents=Object.fromEntries(Object.keys(DOG_TALENTS).map(id=>[id,0]));this.healthMultiplier=Math.max(.8,Math.min(1.2,Number(healthMultiplier)||1));}
  stats(){const stats=dogStats(this.levels);return {...stats,health:Math.round(stats.health*this.healthMultiplier),level:stats.level+this.talentStats().level};}
  cost(id){const config=DOG_UPGRADES[id];return !config||this.levels[id]>=config.max?null:Math.round(config.baseCost*Math.pow(config.costScale,this.levels[id]));}
  unlock(id){const config=DOG_UPGRADES[id];return config?config.unlockRound+(id==='element'?this.levels[id]*4:0):Infinity;}
  buy(id,wallet,round){const cost=this.cost(id);if(cost===null||round<this.unlock(id)||wallet.coins<cost)return false;wallet.coins-=cost;this.levels[id]++;return true;}
  next(id){if(this.cost(id)===null)return null;this.levels[id]++;const next=this.stats();this.levels[id]--;return next;}
  talentStats(){return dogTalentStats(this.talents);}
  talentCost(id){const config=DOG_TALENTS[id];return !config||this.talents[id]>=config.max?null:Math.round(config.baseCost*Math.pow(config.costScale,this.talents[id]));}
  talentUnlock(id){return DOG_TALENTS[id]?.unlockRound??Infinity;}
  buyTalent(id,wallet,round){const cost=this.talentCost(id);if(cost===null||round<this.talentUnlock(id)||!Number.isFinite(wallet?.coins)||wallet.coins<cost)return false;wallet.coins-=cost;this.talents[id]++;return true;}
  talentNext(id){if(this.talentCost(id)===null)return null;this.talents[id]++;const stats=this.talentStats();this.talents[id]--;return stats;}
  talentComparison(id){const config=DOG_TALENTS[id];if(!config)return null;const current=this.talentStats(),next=this.talentNext(id),factor=config.unit==='%'?100:1;return {label:config.label,current:Math.round(current[config.stat]*factor),next:next?Math.round(next[config.stat]*factor):null,unit:config.unit};}
}

export class DogSystem {
  constructor({scene,hero,player,enemies,navigation,combat,toast=()=>{},loot=null,getLoot=null,getPlayerState=null,revivePlayer=null,grantShield=null,metaBonuses={}}){
    Object.assign(this,{scene,hero,player,enemies,navigation,combat,toast});this.training=new DogTraining();this.followOnly=false;this.gait=0;this.trailTime=0;this.visualTier=-1;this.health=DOG_CONFIG.health;this.downed=0;this.attackCooldown=.5;this.attackPose=0;this.hurtCooldown=0;this.navTimer=0;this.seed=5;this.velocity=new THREE.Vector3();this.status='SEGUINDO';this.kills=0;
    Object.assign(this,{loot,getLoot,getPlayerState,revivePlayer,grantShield});this.training=new DogTraining({healthMultiplier:metaBonuses.dogHealthMultiplier});this.health=this.training.stats().health;this.skinColor=metaBonuses.skinColor||null;this.rescueUsed=false;this.rescuing=false;this.rescueProgress=0;this.rescueElapsed=0;this.shieldCooldown=0;this.tauntCooldown=0;this.supportTimer=0;this.markTimer=0;this.fetchDrop=null;
    this.geometries=[];this.materials=[];this.g=new THREE.Group();this.g.position.copy(player.pos).add(new THREE.Vector3(-1.8,0,-1));this.g.position.y=this.floorAt(this.g.position);scene.add(this.g);
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
    this.harness=new THREE.Group();this.g.add(this.harness);this.harness.visible=false;
    for(const z of [-.28,.28])mesh(new THREE.TorusGeometry(.25,.035,4,12),black,0,.41,z,this.harness);
    mesh(new THREE.BoxGeometry(.35,.055,.67),dark,0,.67,0,this.harness);
    this.satchels=new THREE.Group();this.g.add(this.satchels);this.satchels.visible=false;
    for(const side of [-1,1]){mesh(new THREE.BoxGeometry(.15,.22,.26),dark,side*.29,.47,-.1,this.satchels);mesh(new THREE.BoxGeometry(.16,.055,.12),this.accent,side*.29,.48,-.1,this.satchels);}
    this.armor=new THREE.Group();this.g.add(this.armor);this.armor.visible=false;
    const armorMat=material('#536d71');for(const side of [-1,1])mesh(new THREE.BoxGeometry(.055,.22,.5),armorMat,side*.26,.46,.11,this.armor);
    mesh(new THREE.BoxGeometry(.35,.07,.35),armorMat,0,.66,.21,this.armor);mesh(new THREE.BoxGeometry(.13,.025,.16),this.accent,0,.704,.2,this.armor);
    this.beacon=mesh(new THREE.SphereGeometry(.045,6,4),this.accent,0,.76,-.18,this.satchels);this.beacon.visible=false;
  }
  floorAt(position){const value=this.navigation.heightAt?.(position.x,position.z,position.y);return Number.isFinite(value)?value:position.y;}
  runtimeStats(){const stats=this.training.stats(),modifiers=this.combat.game.getModifiers?.()||{};return {...stats,damage:stats.damage*Math.max(.1,Number(modifiers.dogDamage)||1),attackCooldown:stats.attackCooldown*Math.max(.35,Number(modifiers.dogCooldown)||1)};}
  upgradeTalent(id,wallet,round){const cost=this.training.talentCost(id);if(!this.training.buyTalent(id,wallet,round))return false;this.combat.game.reward?.(-cost);this.combat.effects.sound('purchase');this.updateVisuals();this.toast(`${DOG_TALENTS[id].name} — Faro aprendeu uma habilidade!`);this.updateHUD();return true;}
  canRevive(){return !!(this.training.talents.rescue&&!this.rescueUsed&&this.downed<=0&&this.health>0&&this.revivePlayer);}
  onPlayerDowned(){if(!this.canRevive()||this.rescuing)return false;this.rescuing=true;this.rescueProgress=0;this.rescueElapsed=0;this.path=null;this.status='A CAMINHO';this.toast('Faro está vindo! Proteja seu companheiro durante o resgate.');return true;}
  tryRevive(dt){
    if(!this.rescuing)return false;if(this.getPlayerState?.()?.downed===false){this.rescuing=false;this.rescueProgress=0;return false;}const stats=this.training.stats(),talents=this.training.talentStats();this.rescueElapsed+=Math.max(0,dt);
    if(this.downed>0||this.health<=0||this.rescueElapsed>12){this.rescuing=false;this.rescueProgress=0;return false;}
    if(this.g.position.distanceTo(this.player.pos)>1.7||!this.navigation.clearLine(this.g.position,this.player.pos,.18)){this.status='A CAMINHO';this.navigation.move(this,this.player.pos,stats.speed,dt,.25);this.rescueProgress=0;return false;}
    this.status=`RESGATANDO ${Math.min(100,Math.round(this.rescueProgress/talents.reviveTime*100))}%`;this.rescueProgress+=dt;
    if(this.rescueProgress<talents.reviveTime)return false;
    const revived=this.revivePlayer(talents.reviveHealth);this.rescuing=false;this.rescueProgress=0;if(revived===false)return false;this.rescueUsed=true;this.combat.effects.sound('dog');this.combat.effects.nova(this.g.position,'#98d4c5',2);this.toast('Melhor amigo! Faro colocou você de volta na luta.');return true;
  }
  upgrade(id,wallet,round){const cost=this.training.cost(id),before=this.training.stats();if(!this.training.buy(id,wallet,round))return false;const after=this.training.stats();this.health=Math.min(after.health,this.health+after.health-before.health);this.combat.game.reward(-cost);this.combat.effects.sound('purchase');this.updateVisuals();this.toast(`${DOG_UPGRADES[id].name} — Faro evoluiu!`);return true;}
  command(){this.followOnly=!this.followOnly;this.path=null;this.toast(this.followOnly?'Faro, junto! Ele protege sua retaguarda.':'Faro, pode caçar!');}
  heal(wallet,cost=40){if(this.health>=this.training.stats().health||wallet.coins<cost)return false;wallet.coins-=cost;this.health=this.training.stats().health;this.downed=0;this.g.rotation.z=0;this.combat.game.reward(-cost);this.toast('Faro recuperado e pronto para a próxima.');return true;}
  hurt(amount){if(this.downed>0||this.hurtCooldown>0)return;this.health=Math.max(0,this.health-Math.round(amount*(1-this.training.stats().resistance)));this.hurtCooldown=.7;if(this.health<=0){this.downed=DOG_CONFIG.reviveTime;this.status='DESCANSANDO';this.toast('Faro precisa respirar. Ele volta em 9 segundos.');}this.updateHUD();}
  updateVisuals(){
    const stats=this.training.stats(),talents=this.training.talents,tier=stats.element>=3?3:stats.element>=2||stats.level>=9?2:stats.level>=3?1:0;
    this.harness.visible=stats.level>=3;this.satchels.visible=talents.scout+talents.courier+talents.tracker>0;this.armor.visible=talents.barrier+talents.decoy+talents.rescue>0;this.beacon.visible=talents.tracker>0;
    if(tier===this.visualTier&&this.visualSkin===this.skinColor)return;this.visualTier=tier;this.visualSkin=this.skinColor;this.collar.visible=tier>=1||!!this.skinColor;this.heroTrim.visible=tier>=1;this.aura.visible=tier>=2;
    const color=this.skinColor||(tier>=3?'#c1adff':tier>=2?'#9bdeec':'#efbb66');this.accent.color.set(color);this.accent.emissive.set(color);this.accent.emissiveIntensity=tier>=2?.7:.1;
  }
  updateSupport(dt){
    const talents=this.training.talentStats(),playerState=this.getPlayerState?.()||this.player,health=Number(playerState.health??playerState.hp),maxHealth=Number(playerState.maxHealth??playerState.maxHp??100),danger=Number.isFinite(health)&&health/maxHealth<.65;
    this.shieldCooldown=Math.max(0,this.shieldCooldown-dt);this.tauntCooldown=Math.max(0,this.tauntCooldown-dt);this.markTimer-=dt;
    if(talents.shieldAmount&&danger&&this.shieldCooldown<=0&&this.grantShield){if(this.grantShield(talents.shieldAmount,7,'dog')!==false){this.shieldCooldown=talents.shieldCooldown;this.combat.effects.nova(this.player.pos,this.skinColor||'#93cecd',1.3);this.combat.effects.sound('dog');this.toast(`Faro protegeu você: +${talents.shieldAmount} de escudo.`);}}
    if(talents.tauntRadius&&danger&&this.tauntCooldown<=0){const nearby=this.enemies.filter(enemy=>!enemy.disabled&&enemy.g.position.distanceTo(this.g.position)<talents.tauntRadius&&this.navigation.clearLine(this.g.position,enemy.g.position,.1));if(nearby.length){for(const enemy of nearby){enemy.tauntTime=Math.max(enemy.tauntTime||0,2.8);enemy.tauntTarget=this;}this.tauntCooldown=talents.tauntCooldown;this.combat.effects.nova(this.g.position,'#ebc589',talents.tauntRadius);this.combat.effects.sound('dog');this.status='DISTRAINDO';}}
    if(talents.markRange&&this.markTimer<=0){this.markTimer=.5;for(const enemy of this.enemies)if(!enemy.disabled&&enemy.g.position.distanceTo(this.g.position)<talents.markRange&&(enemy.elite||enemy.config?.elite||enemy.modifiers?.length||['ranged','support','miniboss','boss'].includes(enemy.config?.type))){enemy.markedTime=.65;enemy.healthTimer=Math.max(enemy.healthTimer||0,.65);}}
    if(this.followOnly)return null;
    const loot=this.getLoot?.()||this.loot;if(!loot?.nearest||!loot?.collect||(!talents.ammoRange&&!talents.coinRange))return null;
    if(this.enemies.some(enemy=>!enemy.disabled&&enemy.g.position.distanceTo(this.g.position)<3))return null;
    this.supportTimer-=dt;if(this.supportTimer<=0||!this.fetchDrop){this.supportTimer=.45;const choices=[];for(const [type,range] of [['ammo',talents.ammoRange],['money',talents.coinRange]])if(range){const drop=loot.nearest(this.g.position,[type]),pos=drop?.position||drop?.g?.position||drop?.pos;if(pos&&this.g.position.distanceTo(pos)<=range&&this.player.pos.distanceTo(pos)<this.training.stats().leash)choices.push({drop,pos});}choices.sort((a,b)=>this.g.position.distanceToSquared(a.pos)-this.g.position.distanceToSquared(b.pos));this.fetchDrop=choices[0]?.drop||null;}
    const drop=this.fetchDrop,position=drop?.position||drop?.g?.position||drop?.pos;if(!position||drop.collected||drop.active===false){this.fetchDrop=null;return null;}
    this.status='BUSCANDO SUPRIMENTOS';if(this.g.position.distanceTo(position)<1.2&&this.navigation.clearLine(this.g.position,position,.1)){const collected=loot.collect(drop,{collector:'dog',byDog:true});this.fetchDrop=null;if(collected!==false){this.combat.effects.sound('dog');this.status='ENTREGA FEITA';}return 0;}
    return this.navigation.move(this,position,this.training.stats().speed,dt,.25);
  }
  update(dt,time){
    const stats=this.runtimeStats();this.updateVisuals();this.attackCooldown=Math.max(0,this.attackCooldown-dt);this.attackPose=Math.max(0,this.attackPose-dt);this.hurtCooldown=Math.max(0,this.hurtCooldown-dt);
    if(this.downed>0){this.rescuing=false;this.downed-=dt;this.g.rotation.z=THREE.MathUtils.lerp(this.g.rotation.z,1.3,Math.min(1,dt*8));if(this.downed<=0){this.health=Math.ceil(stats.health*.55);this.g.rotation.z=0;const home=this.player.pos.clone().add(new THREE.Vector3(-1.5,0,-1));home.y=this.floorAt(home);this.navigation.freePosition(home,.3);this.g.position.copy(home);this.path=null;this.toast('Faro voltou. Bom cachorro!');}this.updateHUD();return;}
    const homeDistance=this.g.position.distanceTo(this.player.pos);
    if(homeDistance>32){const home=this.player.pos.clone().add(new THREE.Vector3(-2,0,-1));home.y=this.floorAt(home);this.navigation.freePosition(home,.3);this.g.position.copy(home);this.path=null;}
    if(this.rescuing){this.tryRevive(dt);this.gait+=dt*this.velocity.length()*5;this.legs.forEach((leg,i)=>leg.rotation.x=Math.sin(this.gait+(i===0||i===3?0:Math.PI))*.6);this.updateHUD();return;}
    const fetchSpeed=this.updateSupport(dt);
    const candidates=this.followOnly?[]:this.enemies.filter(e=>!e.disabled&&e.g.position.distanceTo(this.player.pos)<stats.leash&&e.g.position.distanceTo(this.g.position)<12);
    candidates.sort((a,b)=>a.g.position.distanceToSquared(this.g.position)-b.g.position.distanceToSquared(this.g.position));const target=candidates[0];
    let speed=fetchSpeed??0;
    if(fetchSpeed!==null){/* Fetching uses the same navigation and leash as combat. */}
    else if(target){
      this.status='CAÇANDO';const distance=target.g.position.distanceTo(this.g.position);
      if(distance>stats.attackRange+target.config.scale*.2||!this.navigation.clearLine(this.g.position,target.g.position,.1))speed=this.navigation.move(this,target.g.position,stats.speed,dt,.25);
      else if(this.attackCooldown<=0&&this.navigation.clearLine(this.g.position,target.g.position,.1)){
        this.status='ATACANDO';this.attackCooldown=stats.attackCooldown;this.attackPose=.25;this.combat.effects.sound('dog');
        const targets=candidates.filter(e=>e.g.position.distanceTo(this.g.position)<stats.attackRange+e.config.scale*.2&&this.navigation.clearLine(this.g.position,e.g.position,.1)).slice(0,stats.targets);
        for(const enemy of targets){const critical=Math.random()<stats.criticalChance,execution=stats.element>=3&&enemy.health/enemy.maxHealth<.16;const amount=execution?enemy.health:stats.damage*(critical?1.7:1);this.combat.damage(enemy,amount,{source:'dog',critical,effect:stats.element?'chain':'kinetic'});this.combat.effects.burst(enemy.g.position.clone().add(new THREE.Vector3(0,.7,0)),stats.element?'#b1e2ef':'#e6c69d',4,.8);if(stats.element){enemy.stunTime=Math.max(enemy.stunTime,.22);this.combat.chain(enemy,stats.damage*.4,stats.element>=3?2:1,4,'dog');}if(stats.element>=2)this.combat.applyStatus(enemy,{effect:'frost',slow:.6,slowDuration:1.8});}
        if(stats.element>=3)this.combat.effects.nova(this.g.position,'#c5aeff',1.4);
      }
    }else{
      this.status=this.followOnly?'JUNTO':'SEGUINDO';const offset=new THREE.Vector3(Math.cos(this.player.cameraYaw)*1.6,0,-Math.sin(this.player.cameraYaw)*1.6);const home=this.player.pos.clone().add(offset);home.y=this.floorAt(home);
      if(this.g.position.distanceTo(home)>1)speed=this.navigation.move(this,home,stats.speed,dt,.25);else this.velocity.multiplyScalar(Math.exp(-dt*8));
      this.health=Math.min(stats.health,this.health+dt*(this.followOnly?2:1));
    }
    this.gait+=dt*(speed> .2?speed*5:3);this.legs.forEach((leg,i)=>leg.rotation.x=speed>.2?Math.sin(this.gait+(i===0||i===3?0:Math.PI))*.6:0);this.tail.rotation.z=Math.sin(time*8)*.35;
    this.g.position.y=this.floorAt(this.g.position);for(const leg of this.legs){const foot=new THREE.Vector3(leg.position.x,0,leg.position.z).applyAxisAngle(new THREE.Vector3(0,1,0),this.g.rotation.y).add(this.g.position);leg.position.y=.3+Math.max(-.14,Math.min(.14,this.floorAt(foot)-this.g.position.y));}
    this.head.rotation.x=this.attackPose>0?-Math.sin(this.attackPose*12)*.25:0;this.body.position.y=.4+(speed>.2?Math.abs(Math.sin(this.gait))*.018:0);
    if(this.aura.visible)this.aura.rotation.z=time*.6;
    this.trailTime-=dt;if(this.visualTier>=3&&speed>3&&this.trailTime<=0){this.trailTime=.22;this.combat.effects.burst(this.g.position,'#c1adff',1,.12);}
    this.updateHUD();
  }
  updateHUD(){if(typeof document==='undefined')return;const stats=this.training.stats();const set=(id,value)=>{const el=document.getElementById(id);if(el&&el.textContent!==String(value))el.textContent=value;};set('dogStatus',this.downed>0?`VOLTA EM ${Math.ceil(this.downed)}s`:this.status);set('dogLevel',`NV ${stats.level}`);set('dogHealth',`${Math.ceil(this.health)} / ${stats.health}`);const fill=document.getElementById('dogHealthFill');if(fill)fill.style.width=`${this.health/stats.health*100}%`;const badge=document.getElementById('dogHud');if(badge){badge.dataset.rescue=this.rescuing?'active':this.rescueUsed?'used':this.canRevive()?'ready':'locked';badge.dataset.role=this.training.talents.scout+this.training.talents.courier?'support':this.training.talents.barrier+this.training.talents.decoy?'survival':'combat';}}
  dispose(){this.g.removeFromParent();this.heroTrim.removeFromParent();this.geometries.forEach(g=>g.dispose());this.materials.forEach(m=>m.dispose());}
}
