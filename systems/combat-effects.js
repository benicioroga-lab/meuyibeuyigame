import * as THREE from 'three';

export class CombatEffects {
  constructor({scene,camera,getAudio,getAudioEngine,getVolume,reduceMotion=()=>false}){
    Object.assign(this,{scene,camera,getAudio,getAudioEngine,getVolume,reduceMotion});this.items=[];this.numbers=[];this.materials=new Map();this.numberSequence=0;this.shake=0;this.killPulse=0;
    this.sphere=new THREE.SphereGeometry(.055,6,4);this.ring=new THREE.TorusGeometry(.25,.018,4,16);this.line=new THREE.CylinderGeometry(.009,.009,1,4);this.mark=new THREE.CircleGeometry(.045,6);
    this.layer=document.getElementById('damageNumbers');
    this.counter={shots:0,hits:0,kills:0};
  }
  material(color){if(!this.materials.has(color))this.materials.set(color,new THREE.MeshBasicMaterial({color,transparent:true,opacity:.85,depthWrite:false}));return this.materials.get(color);}
  add(mesh,life,velocity=null,kind='particle'){
    if(this.items.length>=140){const old=this.items.shift();old.mesh.removeFromParent();}
    this.scene.add(mesh);this.items.push({mesh,life,total:life,velocity,kind});return mesh;
  }
  beam(from,to,color,life=.065,width=1){const delta=to.clone().sub(from),length=delta.length();if(length<.01)return;const mesh=new THREE.Mesh(this.line,this.material(color));mesh.position.copy(from).addScaledVector(delta,.5);mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),delta.normalize());mesh.scale.set(width,length,width);this.add(mesh,life,null,'beam');}
  burst(point,color,count=5,energy=1){if(this.reduceMotion())count=Math.min(count,2);for(let i=0;i<count;i++){const m=new THREE.Mesh(this.sphere,this.material(color));m.position.copy(point);const angle=i*2.399,motion=new THREE.Vector3(Math.cos(angle)*energy,(i%3+.5)*energy,Math.sin(angle)*energy);this.add(m,.22+i*.025,motion);}}
  impact(hit,color){if(!hit)return;const enemy=hit.kind==='enemy'||hit.kind==='boss';this.burst(hit.point,enemy?color:'#ccb999',enemy?5:3,enemy?1.4:.9);if(!enemy){const mark=new THREE.Mesh(this.mark,this.material('#6f6b59'));mark.position.copy(hit.point).addScaledVector(hit.normal,.012);mark.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),hit.normal);this.add(mark,2.5,null,'mark');}}
  nova(point,color,radius=2){const ring=new THREE.Mesh(this.ring,this.material(color));ring.position.copy(point);ring.position.y+=.15;ring.rotation.x=-Math.PI/2;ring.userData.radius=radius;this.add(ring,.32,null,'nova');}
  damageNumber(target,amount,{critical=false,kill=false,source='weapon'}={}){
    if(!this.layer)return;
    // Merge rapid hits to the same actor; at most one current number per damage source.
    const active=this.numbers.find(n=>n.target===target&&n.source===source&&n.age<.16);
    if(active){active.amount+=amount;active.element.textContent=Math.round(active.amount);active.element.classList.toggle('critical',critical||active.critical);active.element.classList.toggle('lethal',kill||active.kill);active.kill||=kill;active.critical||=critical;return;}
    if(this.numbers.length>=22){const old=this.numbers.shift();old.element.remove();}
    const element=document.createElement('span');element.className=`damage-number${critical?' critical':''}${kill?' lethal':''}${source==='dog'?' canine':''}`;element.textContent=Math.round(amount);
    const sequence=this.numberSequence++,offset=(sequence%3-1)*23;
    this.layer.append(element);this.numbers.push({element,target,position:target.g.position.clone(),amount,critical,kill,source,age:0,offset});
  }
  hit({critical=false,kill=false}={}){
    const shell=document.querySelector('.game-shell');shell.classList.add('hit-confirm');shell.classList.toggle('kill-confirm',kill);shell.style.setProperty('--hit-color',kill?'#ffca77':critical?'#ffd779':'#fff1d1');this.hitTime=kill?.2:.09;this.counter.hits++;if(kill){this.counter.kills++;this.killPulse=.035;this.shake=Math.max(this.shake,.04);}
    this.sound(kill?'kill':critical?'critical':'hit');
  }
  sound(type,weapon=null){
    const engine=this.getAudioEngine?.();if(engine){engine.play(type,weapon);return;}
    const context=this.getAudio(),volume=this.getVolume();if(!context||volume<=0)return;
    const now=context.currentTime,gain=context.createGain(),osc=context.createOscillator();let frequency=520,duration=.055,wave='sine',amplitude=.055;
    if(type==='shot'){frequency=weapon.sound;duration=weapon.category==='PESADA'?.15:.075;wave=weapon.effect==='chain'?'sine':weapon.category==='AUTOMÁTICA'?'triangle':'sawtooth';amplitude=weapon.category==='PESADA'?.095:.05;}
    if(type==='reload-start'){frequency=190;duration=.11;wave='triangle';amplitude=.045;}
    if(type==='reload-end'){frequency=420;duration=.07;wave='square';amplitude=.025;}
    if(type==='empty'){frequency=105;duration=.035;wave='square';amplitude=.018;}
    if(type==='critical'){frequency=1080;duration=.075;amplitude=.035;}
    if(type==='kill'){frequency=720;duration=.13;amplitude=.045;}
    if(type==='purchase'){frequency=640;duration=.16;wave='triangle';amplitude=.06;}
    if(type==='dog'){frequency=155;duration=.09;wave='triangle';amplitude=.04;}
    osc.type=wave;osc.frequency.setValueAtTime(frequency,now);osc.frequency.exponentialRampToValueAtTime(Math.max(45,frequency*(type==='purchase'?1.9:.5)),now+duration);
    gain.gain.setValueAtTime(Math.max(.0001,amplitude*volume),now);gain.gain.exponentialRampToValueAtTime(.0001,now+duration);osc.connect(gain).connect(context.destination);osc.start(now);osc.stop(now+duration);osc.onended=()=>{osc.disconnect();gain.disconnect();};
  }
  update(dt){
    this.shake=Math.max(0,this.shake-dt*.35);this.killPulse=Math.max(0,this.killPulse-dt);
    if(this.hitTime>0){this.hitTime-=dt;if(this.hitTime<=0)document.querySelector('.game-shell').classList.remove('hit-confirm','kill-confirm');}
    for(let i=this.items.length-1;i>=0;i--){const item=this.items[i];item.life-=dt;if(item.life<=0){item.mesh.removeFromParent();this.items.splice(i,1);continue;}if(item.velocity){item.mesh.position.addScaledVector(item.velocity,dt);item.velocity.y-=dt*5;item.mesh.scale.setScalar(Math.max(.05,item.life/item.total));}if(item.kind==='nova'){item.mesh.scale.setScalar(1+(1-item.life/item.total)*item.mesh.userData.radius*4);}}
    const width=innerWidth,height=innerHeight;
    for(let i=this.numbers.length-1;i>=0;i--){const n=this.numbers[i];n.age+=dt;if(n.age> .85){n.element.remove();this.numbers.splice(i,1);continue;}n.position.copy(n.target.g.position);n.position.y+=(n.target.config?.scale||1)*2.1;const projected=n.position.clone().project(this.camera);const onScreen=projected.z>-1&&projected.z<1&&Math.abs(projected.x)<1.2&&Math.abs(projected.y)<1.2;n.element.hidden=!onScreen;if(onScreen){n.element.style.transform=`translate(${(projected.x*.5+.5)*width+n.offset}px,${(-projected.y*.5+.5)*height-n.age*(this.reduceMotion()?0:42)}px)`;n.element.style.opacity=String(Math.min(1,(.85-n.age)/.25));}}
  }
  dispose(){this.items.forEach(item=>item.mesh.removeFromParent());this.numbers.forEach(n=>n.element.remove());this.items.length=this.numbers.length=0;this.materials.forEach(m=>m.dispose());for(const g of [this.sphere,this.line,this.ring,this.mark])g.dispose();}
}

export class WeaponView {
  constructor(camera,dog){this.camera=camera;this.dog=dog;this.root=new THREE.Group();this.worldRoot=new THREE.Group();camera.add(this.root);dog.add(this.worldRoot);this.kick=0;this.flashTime=0;this.currentId=null;this.ownedGeometries=[];this.ownedMaterials=[];}
  clear(){this.root.clear();this.worldRoot.clear();this.ownedGeometries.forEach(g=>g.dispose());this.ownedMaterials.forEach(m=>m.dispose());this.ownedGeometries=[];this.ownedMaterials=[];}
  equip(config){
    if(this.currentId===config.id)return;this.currentId=config.id;this.clear();
    const material=(color,emissive=false)=>{const m=new THREE.MeshStandardMaterial({color,roughness:.48,metalness:.25,emissive:emissive?color:'#000000',emissiveIntensity:emissive?.8:0});this.ownedMaterials.push(m);return m;};
    const dark=material('#2e4149'),accent=material(config.color),grip=material('#745c4d'),glow=material(config.color,true);
    const group=new THREE.Group();this.root.add(group);this.body=group;
    const add=(geo,mat,x,y,z)=>{this.ownedGeometries.push(geo);const m=new THREE.Mesh(geo,mat);m.position.set(x,y,z);group.add(m);return m;};
    const long=['boardwalk','ember','voltage'].includes(config.id),heavy=config.id==='hammer'||config.id==='zero';
    add(new THREE.BoxGeometry(heavy?.22:.15,.17,long?.65:.44),dark,0,0,0);
    add(new THREE.BoxGeometry(.16,.08,long?.48:.32),accent,0,.09,-.05);
    add(new THREE.BoxGeometry(.115,.23,.14),grip,0,-.17,.12).rotation.x=-.24;
    this.magazine=add(new THREE.BoxGeometry(.11,config.id==='popcorn'?.34:.2,.13),dark,0,-.16,-.1);
    const barrel=add(new THREE.CylinderGeometry(heavy?.075:.042,heavy?.075:.042,long?.38:.23,10),dark,0,.015,long?-.47:-.33);barrel.rotation.x=Math.PI/2;
    add(new THREE.BoxGeometry(.035,.07,.04),accent,0,.155,-.12);
    if(config.effect==='chain'||config.effect==='frost')for(const side of [-1,1])add(new THREE.BoxGeometry(.026,.04,.28),glow,side*.09,.05,-.12);
    const muzzleZ=long?-.69:-.49;
    this.muzzle=new THREE.Object3D();this.muzzle.position.set(0,.015,muzzleZ);group.add(this.muzzle);
    const flashMaterial=new THREE.MeshBasicMaterial({color:config.color,transparent:true,opacity:.9,depthWrite:false});this.ownedMaterials.push(flashMaterial);
    this.flash=add(new THREE.ConeGeometry(heavy?.14:.09,.2,5),flashMaterial,0,.015,muzzleZ-.07);this.flash.rotation.x=-Math.PI/2;this.flash.visible=false;
    const world=group.clone(true);world.traverse(node=>{node.castShadow=false;});world.scale.setScalar(.75);world.position.set(-.45,.82,-.03);world.rotation.y=Math.PI;this.worldRoot.add(world);
    // Keep muzzle flash camera-local; the world weapon has its own small light mesh.
    this.worldFlash=world.children.at(-1);this.worldFlash.visible=false;
  }
  recoil(config){this.kick=Math.min(.14,this.kick+config.recoil*4);this.flashTime=.045;}
  update(dt,{aiming,active,thirdPerson=false,reload,velocity=0,reduceMotion=false,time=0}){
    this.root.visible=active&&!thirdPerson;this.worldRoot.visible=false;
    this.kick*=Math.exp(-dt*22);this.flashTime=Math.max(0,this.flashTime-dt);
    if(!this.body)return;
    const progress=reload?1-reload.remaining/reload.total:0,tilt=reload?Math.sin(progress*Math.PI):0;
    const bob=reduceMotion?0:Math.sin(time*9)*Math.min(velocity*.0015,.012);
    // Weapon remains below/right of the reticle, including ADS.
    this.root.scale.setScalar(.72);
    this.root.position.set(aiming?.23:.38,-.28-tilt*.16+bob,-.65+this.kick);
    this.root.rotation.set(this.kick*1.6+tilt*.3,0,-tilt*.5);
    this.magazine.position.y=-.16-tilt*.17;
    this.flash.visible=this.flashTime>0;this.worldFlash.visible=this.flashTime>0;
  }
  muzzlePosition(){this.root.updateWorldMatrix(true,true);return this.muzzle.getWorldPosition(new THREE.Vector3());}
  dispose(){this.clear();this.root.removeFromParent();this.worldRoot.removeFromParent();}
}
