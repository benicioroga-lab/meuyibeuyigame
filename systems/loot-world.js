import * as THREE from 'three';
import {RARITIES,ATTACHMENTS,MANUFACTURERS,ELEMENTS,LEGENDARY_PERKS} from './loot-config.js';
import {rollWeapon,computeWeaponStats,compareWeapons} from './weapon-rolls.js';
import {POWERUPS} from './run-config.js';

const rarityOrder=Object.keys(RARITIES),automaticTypes=new Set(['money','ammo']);
const plain=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const vector=value=>value?.clone?value.clone():new THREE.Vector3(Number(value?.x)||0,Number(value?.y)||0,Number(value?.z)||0);
const sum=value=>Math.max(0,Math.round(Number(value)||0));
const shortStats=(key,value)=>key==='criticalChance'?`${value}%`:key==='fireRate'?`${Math.round(value*60)} RPM`:key==='reloadTime'?`${value}s`:key==='criticalMultiplier'?`${value}×`:String(value);

/** World loot owns shared meshes, per-drop labels and collection rules; run rewards stay in the director. */
export class LootWorld {
  constructor({scene,player,combat,world=null,director=null,getDirector=()=>director,state=null,reward=null,toast=()=>{},onCollect=()=>{},dog=null,getDog=()=>dog,random=Math.random,maxDrops=60,document:doc=globalThis.document,interactionKey='F'}={}){
    Object.assign(this,{scene,player,combat,world,getDirector,state,toast,onCollect,getDog,random,doc,interactionKey});
    this.reward=reward||((amount)=>{if(state)state.coins+=amount;});this.maxDrops=Math.max(4,Math.min(100,Math.floor(maxDrops)));this.drops=[];this.serial=0;this.time=0;this.hudClock=0;this.lastPrompt='';this.failedPickupAt=-Infinity;this.spawnSoundAt=-Infinity;
    this.group=new THREE.Group();this.group.name='World loot';scene.add(this.group);
    this.geometry={box:new THREE.BoxGeometry(1,1,1),coin:new THREE.CylinderGeometry(.2,.2,.055,9),ring:new THREE.TorusGeometry(.39,.019,4,22),beam:new THREE.CylinderGeometry(.06,.16,1,8,1,true),orb:new THREE.OctahedronGeometry(.27,0)};
    this.materials=new Map();this.dark=this.material('#253b36');this.brass=this.material('#dcc17e');this._cameraDirection=new THREE.Vector3();
  }
  material(color,beam=false){const key=`${color}:${beam}`;if(!this.materials.has(key))this.materials.set(key,beam?new THREE.MeshBasicMaterial({color,transparent:true,opacity:.15,depthWrite:false,side:THREE.DoubleSide}):new THREE.MeshStandardMaterial({color,roughness:.48,metalness:.3,emissive:color,emissiveIntensity:.18}));return this.materials.get(key);}
  sound(kind,options={}){kind=({coin:'collect',ammo:'reload-end','powerup-drop':'loot'}[kind]||kind);const engine=this.combat.game?.getAudioEngine?.();if(engine?.play)engine.play(kind,options);else this.combat.effects?.sound?.(kind,options);}
  floor(position){const pos=vector(position),height=this.world?.heightAt?.(pos.x,pos.z,pos.y);if(Number.isFinite(height))pos.y=height;return pos;}
  lineOfSight(from,to){const start=vector(from).add(new THREE.Vector3(0,.5,0)),end=vector(to).add(new THREE.Vector3(0,.35,0));return this.combat.hitWorld?.lineOfSight?.(start,end)??true;}
  priority(drop){return drop.type==='weapon'?3+rarityOrder.indexOf(drop.roll.rarity):drop.type==='powerup'?7:drop.type==='attachment'?3:drop.type==='ammo'?2:1;}
  makeRoom(next){
    if(this.drops.length<this.maxDrops)return true;
    const oldest=[...this.drops].sort((a,b)=>this.priority(a)-this.priority(b)||b.age-a.age)[0];
    if(this.priority(oldest)>this.priority(next))return false;this.remove(oldest);return true;
  }
  label(text,color){
    if(!this.doc?.createElement)return null;
    const canvas=this.doc.createElement('canvas'),ctx=canvas.getContext?.('2d');if(!ctx)return null;
    canvas.width=384;canvas.height=80;ctx.font='600 22px sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';ctx.lineWidth=5;ctx.strokeStyle='#12201be0';ctx.strokeText(text,192,40);ctx.fillStyle=color;ctx.fillText(text,192,40);
    const texture=new THREE.CanvasTexture(canvas);texture.colorSpace=THREE.SRGBColorSpace;const material=new THREE.SpriteMaterial({map:texture,transparent:true,depthTest:true,depthWrite:false});const sprite=new THREE.Sprite(material);sprite.scale.set(2.55,.53,1);return sprite;
  }
  mesh(parent,geometry,material,x,y,z,sx=1,sy=1,sz=1){const mesh=new THREE.Mesh(geometry,material);mesh.position.set(x,y,z);mesh.scale.set(sx,sy,sz);parent.add(mesh);return mesh;}
  create(type,position,data={}){
    const drop={id:`drop-${++this.serial}`,type,position:this.floor(position),age:0,ttl:90,collected:false,phase:this.random()*Math.PI*2,...data};drop.pos=drop.position;
    if(!this.makeRoom(drop))return null;
    const color=drop.color||'#e6c887',mat=this.material(color),group=new THREE.Group(),model=new THREE.Group();group.position.copy(drop.position);group.add(model);drop.g=group;drop.model=model;this.group.add(group);
    const ring=this.mesh(group,this.geometry.ring,mat,0,.08,0);ring.rotation.x=Math.PI/2;drop.ring=ring;
    if(type==='money'){
      for(let i=0;i<Math.min(4,Math.ceil(drop.amount/45));i++)this.mesh(model,this.geometry.coin,this.brass,0,.06*i,0);model.position.y=.24;
    }else if(type==='weapon'){
      this.mesh(model,this.geometry.box,this.dark,0,.03,0,.62,.12,.19);this.mesh(model,this.geometry.box,mat,.3,.09,0,.57,.075,.09);this.mesh(model,this.geometry.box,mat,-.31,.04,0,.19,.17,.16);this.mesh(model,this.geometry.box,this.dark,-.06,-.11,0,.13,.2,.11);model.rotation.z=.13;model.position.y=.62;
    }else if(type==='ammo'){
      this.mesh(model,this.geometry.box,mat,0,0,0,.4,.26,.31);for(const x of[-.1,0,.1])this.mesh(model,this.geometry.box,this.brass,x,.2,0,.05,.16,.08);model.position.y=.42;
    }else if(type==='attachment'){
      this.mesh(model,this.geometry.box,mat,0,0,0,.37,.12,.17);this.mesh(model,this.geometry.orb,this.dark,0,.06,0,.5,.5,.5);model.position.y=.6;
    }else{this.mesh(model,this.geometry.orb,mat,0,0,0);model.position.y=.7;}
    drop.baseY=model.position.y;
    if(!automaticTypes.has(type)){
      const beamHeight=type==='weapon'&&rarityOrder.indexOf(drop.roll.rarity)>=4?3.4:type==='powerup'?2.8:1.8;drop.beam=this.mesh(group,this.geometry.beam,this.material(color,true),0,beamHeight/2,0,1,beamHeight,1);
      drop.label=this.label(drop.labelText||drop.name||type,color);if(drop.label){drop.label.position.y=1.3;group.add(drop.label);}
    }
    this.drops.push(drop);
    if((type==='powerup'||type==='weapon'&&rarityOrder.indexOf(drop.roll.rarity)>=4)&&this.time-this.spawnSoundAt>.5){this.sound(type==='powerup'?'powerup-drop':'legendary',{rarity:drop.roll?.rarity,position:drop.position});this.spawnSoundAt=this.time;}
    return drop;
  }
  spawnWeapon(roll,position){const stats=computeWeaponStats(roll);if(!stats)return null;const rarity=RARITIES[stats.rarity]||RARITIES.common;return this.create('weapon',position,{roll:structuredClone(roll),name:stats.name,rarity:stats.rarity,color:rarity.color,labelText:`${rarity.symbol} ${rarity.name.toUpperCase()} · ${stats.name}`,ttl:rarityOrder.indexOf(stats.rarity)>=4?360:180});}
  spawnPowerup(id,position){const config=POWERUPS[id];return config?this.create('powerup',position,{powerupId:id,name:config.name,color:config.color,labelText:`${config.icon} ${config.name.toUpperCase()}`,ttl:35}):null;}
  spawnAttachment(id,position,manufacturer='remendo'){const config=ATTACHMENTS[id];return config?this.create('attachment',position,{attachmentId:id,manufacturer,name:config.name,color:'#97c6d5',labelText:`◇ PEÇA · ${config.name}`,ttl:150}):null;}
  spawnAmmo(position,fraction=1.5){return this.create('ammo',position,{fraction,name:'Munição',color:'#a4c49c',ttl:110});}
  spawnMoney(amount,position){
    amount=sum(amount);if(amount<=0)return null;const pos=this.floor(position),near=this.drops.find(drop=>drop.type==='money'&&drop.position.distanceToSquared(pos)<1.8&&Math.abs(drop.position.y-pos.y)<.4&&this.lineOfSight(drop.position,pos));
    if(near){near.amount+=amount;near.age=0;return near;}return this.create('money',pos,{amount,name:'Petiscos',color:'#e6c887',ttl:105});
  }
  // Optional standalone hook. The main game instead feeds explicit, director-approved drop events.
  onEnemyKilled(enemy,details={}){
    const director=this.getDirector(),position=enemy.g?.position||enemy.position,round=details.round||director?.round||1;
    const money=this.spawnMoney(details.reward??enemy.config?.reward??0,position);
    if(details.weaponRoll)this.spawnWeapon(details.weaponRoll,position);
    else if(details.loot===true)this.spawnWeapon(rollWeapon({round,difficulty:director?.difficultyId||'normal',chaos:director?.chaos||0,quality:director?.modifiers?.lootQuality||0,random:this.random}),position);
    if(details.powerupId)this.spawnPowerup(details.powerupId,position);if(details.ammo)this.spawnAmmo(position);return money;
  }
  nearest(position=this.player.pos,types=null,maxDistance=Infinity){
    const allowed=types?new Set(Array.isArray(types)?types:[types]):null,pos=vector(position),needsAmmo=[...this.combat.arsenal.inventory.values()].some(entry=>entry.reserve<this.combat.arsenal.stats(entry.id).maxReserve);
    return this.drops.filter(drop=>!drop.collected&&(!allowed||allowed.has(drop.type))&&(drop.type!=='ammo'||needsAmmo)&&Math.abs(drop.position.y-pos.y)<1.6&&drop.position.distanceTo(pos)<=maxDistance&&this.lineOfSight(pos,drop.position)).sort((a,b)=>a.position.distanceToSquared(pos)-b.position.distanceToSquared(pos))[0]||null;
  }
  focusDrop(){
    const camera=this.combat.game?.camera,origin=camera?.position||this.player.pos;
    if(camera)camera.getWorldDirection(this._cameraDirection);
    let best=null,score=Infinity;
    for(const drop of this.drops){
      if(drop.collected||automaticTypes.has(drop.type)||Math.abs(drop.position.y-this.player.pos.y)>1.6)continue;
      const distance=drop.position.distanceTo(this.player.pos);if(distance>3||!this.lineOfSight(this.player.pos,drop.position))continue;
      const toward=drop.position.clone().add(new THREE.Vector3(0,.5,0)).sub(origin).normalize(),alignment=camera?toward.dot(this._cameraDirection):1;if(alignment<.4)continue;
      const candidate=distance+(1-alignment)*3;if(candidate<score){score=candidate;best=drop;}
    }
    return best;
  }
  getHUDComparison(drop=this.focusDrop()){
    if(!drop||drop.type!=='weapon')return null;const stats=computeWeaponStats(drop.roll,{modifiers:this.combat.arsenal.activeModifiers?.()||{}}),current=this.combat.arsenal.stats(),rarity=RARITIES[stats.rarity];
    return {id:drop.id,name:stats.name,rarity:rarity.name,rarityId:rarity.id,symbol:rarity.symbol,color:rarity.color,manufacturer:stats.manufacturerName,element:ELEMENTS[stats.element]?.name||'Cinético',perk:LEGENDARY_PERKS[stats.perk]||null,attachments:stats.attachments,stats,current,rows:compareWeapons(current,stats)};
  }
  collect(drop,{collector='player',byDog=false,position=null,equip=false}={}){
    if(!drop||drop.collected||!this.drops.includes(drop))return false;
    const dog=collector==='dog'||byDog,actor=position||(dog?this.getDog()?.g.position:null)||this.player.pos;
    if(vector(actor).distanceTo(drop.position)>3||Math.abs(actor.y-drop.position.y)>1.6||!this.lineOfSight(actor,drop.position))return false;
    let result=false;
    if(drop.type==='money'){this.reward(drop.amount);result=true;}
    if(drop.type==='ammo')result=this.combat.arsenal.addAmmo(drop.fraction)>0;
    if(drop.type==='weapon'){
      result=this.combat.arsenal.addLoot(drop.roll);
      if(result&&equip)this.combat.arsenal.equip(result);
      if(!result&&this.time-this.failedPickupAt>2){this.toast('Mochila cheia. Recicle uma arma no inventário · Tab.');this.failedPickupAt=this.time;}
    }
    if(drop.type==='attachment'){
      result=this.combat.arsenal.addAttachment(drop.attachmentId,drop.manufacturer);
      if(!result&&this.time-this.failedPickupAt>2){this.toast('Bolsa de peças cheia. Instale suas peças na aba Peças.');this.failedPickupAt=this.time;}
    }
    if(drop.type==='powerup')result=this.getDirector()?.activatePowerup?.(drop.powerupId)??false;
    if(!result)return false;
    if(drop.type==='weapon'){this.toast(`${RARITIES[drop.roll.rarity]?.name.toUpperCase()} · ${drop.name}${equip?' equipada':' na mochila · Tab para equipar'}`);this.sound('loot',{rarity:drop.roll.rarity,position:drop.position});}
    if(drop.type==='attachment'){this.toast(`PEÇA ENCONTRADA · ${drop.name} · Tab → Peças`);this.sound('loot',{rarity:'rare',position:drop.position});}
    if(drop.type==='ammo'){this.toast(dog?'Faro trouxe munição.':'Munição recolhida.');this.sound('ammo');}
    if(drop.type==='money')this.sound('coin',{amount:drop.amount});
    if(drop.type==='powerup'){this.toast(`POWER-UP! ${drop.name.toUpperCase()}`);this.sound('powerup',{powerup:drop.powerupId});}
    drop.collected=true;this.onCollect(drop,{collector:dog?'dog':'player',result});this.remove(drop);this.combat.updateHUD?.();return true;
  }
  interact(){const drop=this.focusDrop();if(!drop)return false;this.collect(drop,{equip:drop.type==='weapon'});return true;}
  update(dt,time=this.time+dt){
    if(!Number.isFinite(dt)||dt<=0)return;this.time=time;const modifiers=this.getDirector()?.modifiers||{},magnet=Boolean(modifiers.magnet),player=this.player.pos;
    for(let i=this.drops.length-1;i>=0;i--){
      const drop=this.drops[i];drop.age+=dt;if(drop.age>drop.ttl){this.remove(drop);continue;}
      drop.model.rotation.y=time*(drop.type==='weapon'?.35:.85)+drop.phase;drop.model.position.y=drop.baseY+Math.sin(time*2.2+drop.phase)*.075;drop.ring.scale.setScalar(1+Math.sin(time*2+drop.phase)*.07);
      if(drop.label)drop.label.visible=drop.position.distanceToSquared(player)<18*18;
      const auto=automaticTypes.has(drop.type),distance=drop.position.distanceTo(player),height=Math.abs(drop.position.y-player.y);
      if((auto||magnet)&&height<1.6&&distance<(magnet?11:drop.type==='money'?1.85:1.4)&&this.lineOfSight(player,drop.position)){
        if(magnet&&distance>1.25){const step=Math.min(distance-1,dt*9);drop.position.lerp(player,step/distance);drop.position.y=this.floor(drop.position).y;drop.g.position.copy(drop.position);}
        else if(auto||drop.type==='attachment'||drop.type==='powerup')this.collect(drop);
      }
      // Expiration gets a slow pulse, never a distracting strobe.
      drop.g.visible=drop.ttl-drop.age>8||Math.sin(time*4)>-.25;
    }
    this.hudClock-=dt;if(this.hudClock<=0){this.updateHUD();this.hudClock=.12;}
  }
  updateHUD(){
    const prompt=this.doc?.getElementById?.('lootPrompt'),comparison=this.doc?.getElementById?.('lootComparison');if(!prompt&&!comparison)return;
    const drop=this.focusDrop(),data=this.getHUDComparison(drop),signature=drop?`${drop.id}:${this.combat.arsenal.currentId}:${this.combat.arsenal.current.roll?.revision||0}:${data?data.rows.map(row=>`${row.before},${row.after}`).join(';'):''}`:'';
    if(prompt){prompt.classList.add('loot-prompt');prompt.hidden=!drop;if(drop){prompt.style.setProperty('--loot-color',drop.color);if(signature!==this.lastPrompt){const rarity=data?`${data.symbol} ${data.rarity.toUpperCase()}`:drop.type==='powerup'?'POWER-UP':'PEÇA ENCONTRADA';prompt.innerHTML=`<small>${plain(rarity)}</small><strong>${plain(drop.name)}</strong><span><kbd>${plain(this.interactionKey)}</kbd>${drop.type==='weapon'?'RECOLHER E EQUIPAR':drop.type==='powerup'?'ATIVAR':'GUARDAR PEÇA'}${drop.type==='weapon'?'<br>Tab · mochila e favoritos':''}</span>`;}}}
    if(comparison){comparison.classList.add('loot-comparison');comparison.hidden=!data;if(data&&signature!==this.lastPrompt){comparison.style.setProperty('--loot-color',data.color);comparison.innerHTML=`<small>${data.symbol} ${plain(data.rarity.toUpperCase())} · ${plain(data.element.toUpperCase())}</small><h3>${plain(data.name)}</h3><p>${plain(data.manufacturer)}</p>${data.perk?`<p class="legendary-trait"><b>★ ${plain(data.perk.name)}</b>${plain(data.perk.description)}</p>`:''}<div class="roll-comparison"><div class="comparison-heading"><span>EQUIPADA</span><strong>NO CHÃO</strong></div>${data.rows.slice(0,6).map(row=>`<div class="comparison-row ${row.delta===0?'same':row.better?'better':'worse'}"><span>${plain(row.label)}</span><b>${plain(shortStats(row.key,row.before))}</b><i>${row.delta===0?'=':row.better?'↑':'↓'}</i><strong>${plain(shortStats(row.key,row.after))}</strong></div>`).join('')}</div>`;}}
    this.lastPrompt=signature;
  }
  remove(drop){const index=this.drops.indexOf(drop);if(index<0)return false;this.drops.splice(index,1);drop.g.removeFromParent();if(drop.label){drop.label.material.map?.dispose();drop.label.material.dispose();}drop.removed=true;drop.active=false;return true;}
  dispose(){for(const drop of [...this.drops])this.remove(drop);this.group.removeFromParent();Object.values(this.geometry).forEach(geometry=>geometry.dispose());this.materials.forEach(material=>material.dispose());this.materials.clear();for(const id of['lootPrompt','lootComparison']){const element=this.doc?.getElementById?.(id);if(element)element.hidden=true;}}
}
