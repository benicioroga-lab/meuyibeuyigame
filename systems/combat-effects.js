import * as THREE from 'three';

export class CombatEffects {
  constructor({scene,camera,getAudio,getAudioEngine,getVolume,reduceMotion=()=>false,showNumbers=()=>true}){
    Object.assign(this,{scene,camera,getAudio,getAudioEngine,getVolume,reduceMotion,showNumbers});this.items=[];this.numbers=[];this.materials=new Map();this.numberSequence=0;this.shake=0;this.killPulse=0;
    this.sphere=new THREE.SphereGeometry(.055,6,4);this.ring=new THREE.TorusGeometry(.25,.018,4,16);this.line=new THREE.CylinderGeometry(.009,.009,1,4);this.mark=new THREE.CircleGeometry(.045,6);
    this.shellGeometry=new THREE.CylinderGeometry(.016,.016,.062,6);this.layer=globalThis.document?.getElementById('damageNumbers');
    this.counter={shots:0,hits:0,kills:0};
  }
  material(color){if(!this.materials.has(color))this.materials.set(color,new THREE.MeshBasicMaterial({color,transparent:true,opacity:.85,depthWrite:false}));return this.materials.get(color);}
  add(mesh,life,velocity=null,kind='particle'){
    if(this.items.length>=140){const old=this.items.shift();old.mesh.removeFromParent();}
    this.scene.add(mesh);this.items.push({mesh,life,total:life,velocity,kind});return mesh;
  }
  beam(from,to,color,life=.065,width=1){const delta=to.clone().sub(from),length=delta.length();if(length<.01)return;const mesh=new THREE.Mesh(this.line,this.material(color));mesh.position.copy(from).addScaledVector(delta,.5);mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0,1,0),delta.normalize());mesh.scale.set(width,length,width);this.add(mesh,life,null,'beam');}
  burst(point,color,count=5,energy=1){if(this.reduceMotion())count=Math.min(count,2);for(let i=0;i<count;i++){const m=new THREE.Mesh(this.sphere,this.material(color));m.position.copy(point);const angle=i*2.399,motion=new THREE.Vector3(Math.cos(angle)*energy,(i%3+.5)*energy,Math.sin(angle)*energy);this.add(m,.22+i*.025,motion);}}
  shell(point,camera,weapon){
    if(!point||weapon.effect==='chain'||weapon.effect==='frost')return;
    const mesh=new THREE.Mesh(this.shellGeometry,this.material(weapon.family==='shotgun'?'#cd8865':'#b9a16a'));mesh.position.copy(point);
    const right=new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld,0),velocity=right.multiplyScalar(1.3).add(new THREE.Vector3(0,.75,0));
    this.add(mesh,.65,velocity,'shell');
  }
  impact(hit,color){if(!hit)return;const enemy=hit.kind==='enemy'||hit.kind==='boss';this.burst(hit.point,enemy?color:'#ccb999',enemy?5:3,enemy?1.4:.9);if(!enemy){const mark=new THREE.Mesh(this.mark,this.material('#6f6b59'));mark.position.copy(hit.point).addScaledVector(hit.normal,.012);mark.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),hit.normal);this.add(mark,2.5,null,'mark');}}
  nova(point,color,radius=2){const ring=new THREE.Mesh(this.ring,this.material(color));ring.position.copy(point);ring.position.y+=.15;ring.rotation.x=-Math.PI/2;ring.userData.radius=radius;this.add(ring,.32,null,'nova');}
  damageNumber(target,amount,{critical=false,kill=false,source='weapon',shield=false}={}){
    if(!this.layer||!this.showNumbers())return;
    // Merge rapid hits to the same actor; at most one current number per damage source.
    const active=this.numbers.find(n=>n.target===target&&n.source===source&&n.shield===shield&&n.age<.16);
    if(active){active.amount+=amount;active.element.textContent=Math.round(active.amount);active.element.classList.toggle('critical',critical||active.critical);active.element.classList.toggle('lethal',kill||active.kill);active.kill||=kill;active.critical||=critical;return;}
    if(this.numbers.length>=22){const old=this.numbers.shift();old.element.remove();}
    const element=document.createElement('span');element.className=`damage-number${critical?' critical':''}${kill?' lethal':''}${source==='dog'?' canine':''}${shield?' shield':''}`;element.textContent=Math.round(amount);if(shield)element.style.color='#abd9ff';
    const sequence=this.numberSequence++,offset=(sequence%3-1)*23;
    this.layer.append(element);this.numbers.push({element,target,position:target.g.position.clone(),amount,critical,kill,source,shield,age:0,offset});
  }
  hit({critical=false,kill=false,headshot=false,shield=false}={}){
    const priority=kill?4:headshot?3:critical?2:shield?0:1;
    if(!(this.hitTime>0)||priority>=(this.hitPriority||0)){
      const shell=globalThis.document?.querySelector('.game-shell');shell?.classList.add('hit-confirm');shell?.classList.toggle('kill-confirm',kill);shell?.classList.toggle('head-confirm',headshot);shell?.style.setProperty('--hit-color',shield?'#abd9ff':kill?'#ffca77':critical?'#ffd779':'#fff1d1');this.hitPriority=priority;
    }
    this.hitTime=Math.max(this.hitTime||0,kill?.2:.09);this.counter.hits++;if(kill){this.counter.kills++;this.killPulse=this.reduceMotion()?0:.035;this.shake=Math.max(this.shake,this.reduceMotion()?0:.04);}
    this.sound(headshot?'headshot':kill?'kill':critical?'critical':'hit');
    if(headshot&&kill)this.accolade('NA CABEÇA');
  }
  accolade(label){
    if(!globalThis.document)return;
    if(!this.accoladeNode){this.accoladeNode=document.getElementById('combatAccolade');if(!this.accoladeNode){this.accoladeNode=document.createElement('div');this.accoladeNode.id='combatAccolade';this.accoladeNode.className='combat-accolade';Object.assign(this.accoladeNode.style,{position:'absolute',top:'38%',left:'50%',transform:'translateX(-50%)',color:'#f9d489',font:'600 14px var(--display)',letterSpacing:'.13em',textShadow:'0 2px 5px #10252e',pointerEvents:'none'});(document.getElementById('gameHud')||document.querySelector('.game-shell'))?.append(this.accoladeNode);}}
    this.accoladeNode.textContent=label;this.accoladeNode.hidden=false;this.accoladeTime=.75;
  }
  sound(type,weapon=null){
    const engine=this.getAudioEngine?.();if(engine){engine.play(type,weapon);return;}
    const context=this.getAudio?.(),volume=this.getVolume?.()??0;if(!context||volume<=0)return;
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
    if(this.hitTime>0){this.hitTime-=dt;if(this.hitTime<=0)globalThis.document?.querySelector('.game-shell')?.classList.remove('hit-confirm','kill-confirm','head-confirm');}
    if(this.accoladeTime>0){this.accoladeTime-=dt;if(this.accoladeNode){this.accoladeNode.hidden=this.accoladeTime<=0;this.accoladeNode.style.opacity=String(Math.min(1,this.accoladeTime/.15));}}
    for(let i=this.items.length-1;i>=0;i--){const item=this.items[i];item.life-=dt;if(item.life<=0){item.mesh.removeFromParent();this.items.splice(i,1);continue;}if(item.velocity){item.mesh.position.addScaledVector(item.velocity,dt);item.velocity.y-=dt*5;if(item.kind==='shell'){item.mesh.rotation.x+=dt*12;item.mesh.rotation.z+=dt*8;}else item.mesh.scale.setScalar(Math.max(.05,item.life/item.total));}if(item.kind==='nova'){item.mesh.scale.setScalar(1+(1-item.life/item.total)*item.mesh.userData.radius*4);}}
    const width=globalThis.innerWidth||1280,height=globalThis.innerHeight||720;
    for(let i=this.numbers.length-1;i>=0;i--){const n=this.numbers[i];n.age+=dt;if(n.age> .85){n.element.remove();this.numbers.splice(i,1);continue;}n.position.copy(n.target.g.position);n.position.y+=(n.target.config?.scale||1)*2.1;const projected=n.position.clone().project(this.camera);const onScreen=projected.z>-1&&projected.z<1&&Math.abs(projected.x)<1.2&&Math.abs(projected.y)<1.2;n.element.hidden=!onScreen;if(onScreen){n.element.style.transform=`translate(${(projected.x*.5+.5)*width+n.offset}px,${(-projected.y*.5+.5)*height-n.age*(this.reduceMotion()?0:42)}px)`;n.element.style.opacity=String(Math.min(1,(.85-n.age)/.25));}}
  }
  dispose(){this.items.forEach(item=>item.mesh.removeFromParent());this.numbers.forEach(n=>n.element.remove());this.accoladeNode?.remove();this.items.length=this.numbers.length=0;this.materials.forEach(m=>m.dispose());this.materials.clear();for(const g of [this.sphere,this.line,this.ring,this.mark,this.shellGeometry])g.dispose();}
}

export class WeaponView {
  constructor(camera,dog){
    this.camera=camera;this.dog=dog;this.root=new THREE.Group();this.worldRoot=new THREE.Group();camera.add(this.root);dog?.add(this.worldRoot);
    this.kick=0;this.flashTime=0;this.currentId=null;this.signature=null;this.ownedGeometries=[];this.ownedMaterials=[];this.equipTime=0;this.inspection=0;this.ads=0;this.reloadProgress=0;
  }
  clear(){this.root.clear();this.worldRoot.clear();this.ownedGeometries.forEach(g=>g.dispose());this.ownedMaterials.forEach(m=>m.dispose());this.ownedGeometries=[];this.ownedMaterials=[];}
  equip(config,immediate=false){
    const signature=`${config.instanceId||config.id}:${config.revision||0}`;if(this.signature===signature)return;
    if(this.body&&!immediate&&(config.instanceId||config.id)!==this.currentId){if(this.pendingConfig?.id===config.id)return;this.pendingConfig=config;this.holsterTime=.09;return;}
    this.pendingConfig=null;this.holsterTime=0;
    this.signature=signature;this.currentId=config.instanceId||config.id;this.config=config;this.clear();this.equipDuration=config.equipTime||.32;this.equipTime=this.equipDuration;this.inspection=0;this.kick=0;
    this.family=config.family||(['hammer','zero'].includes(config.baseId||config.id)?'heavy':config.id==='popcorn'?'smg':config.id==='biscuit'?'pistol':'rifle');
    const heavy=this.family==='heavy',long=['rifle','shotgun','sniper'].includes(this.family),sniper=this.family==='sniper',shotgun=this.family==='shotgun';
    const material=(color,emissive=false)=>{const m=new THREE.MeshStandardMaterial({color,roughness:.42,metalness:.38,emissive:emissive?color:'#000000',emissiveIntensity:emissive?.5:0});this.ownedMaterials.push(m);return m;};
    const dark=material('#26343a'),steel=material('#6f7c7c'),accent=material(config.color||'#eab96f'),grip=material('#554b43'),glow=material(config.color||'#eab96f',true);
    const group=new THREE.Group();this.root.add(group);this.body=group;
    const add=(geo,mat,x,y,z,parent=group)=>{this.ownedGeometries.push(geo);const m=new THREE.Mesh(geo,mat);m.position.set(x,y,z);parent.add(m);return m;};
    const box=(w,h,d,mat,x,y,z,parent)=>add(new THREE.BoxGeometry(w,h,d),mat,x,y,z,parent);
    const tube=(radius,length,mat,x,y,z,parent)=>{const mesh=add(new THREE.CylinderGeometry(radius,radius,length,10),mat,x,y,z,parent);mesh.rotation.x=Math.PI/2;return mesh;};
    box(heavy?.23:.16,.15,long?.61:.4,dark,0,0,0);box(.17,.045,long?.49:.32,accent,0,.093,-.01);
    box(.115,.24,.135,grip,0,-.17,.12).rotation.x=-.24;
    // Machined rails and an ejection port provide silhouette detail without expensive imported meshes.
    box(.009,.055,.11,steel,.085,.023,.035);for(let i=0;i<(long?5:3);i++)box(.175,.012,.018,steel,0,.122,-.12+i*.047);
    if(long){box(.12,.105,.27,grip,0,-.015,.4);box(.145,.2,.05,dark,0,-.03,.55);}
    const magazineGroup=new THREE.Group();group.add(magazineGroup);this.magazine=magazineGroup;this.magazine.position.set(0,-.16,-.1);
    if(heavy){const drum=add(new THREE.CylinderGeometry(.13,.13,.18,12),dark,0,-.07,0,magazineGroup);drum.rotation.z=Math.PI/2;}
    else if(!shotgun){box(.1,this.family==='smg'?.3:.22,.13,dark,0,-.06,0,magazineGroup);box(.112,.025,.142,accent,0,-.17,0,magazineGroup);}
    const barrelLength=sniper?.64:shotgun?.55:long?.37:.23,barrelCenter=long?-.4:-.3,muzzleZ=barrelCenter-barrelLength/2;
    tube(heavy?.07:shotgun?.054:.039,barrelLength,steel,0,.015,barrelCenter);tube(.058,.09,dark,0,.015,muzzleZ+.025);
    this.pump=new THREE.Group();group.add(this.pump);this.pump.position.set(0,-.067,-.38);
    if(shotgun){tube(.046,.45,dark,0,-.015,0,this.pump);box(.15,.08,.23,grip,0,-.013,0,this.pump);for(let i=0;i<5;i++)box(.16,.01,.014,accent,0,-.058,-.085+i*.04,this.pump);}
    this.bolt=box(.055,.038,.065,steel,.11,.04,.1);
    if(sniper){tube(.063,.26,dark,0,.19,-.08);tube(.073,.04,glow,0,.19,-.23);box(.08,.06,.12,steel,0,.125,-.08);}
    else{box(.025,.05,.026,accent,0,.145,-.17);box(.07,.036,.025,dark,0,.135,.12);}
    if(['chain','frost','corrosive','shock','cryo'].includes(config.element||config.effect))for(const side of [-1,1])box(.015,.032,.23,glow,side*.092,.046,-.12);
    // Attachments affect the view as well as stats. The looter layer owns their exact bonuses.
    const attachments=JSON.stringify(config.attachments||{});
    if(/laser/i.test(attachments))box(.035,.04,.09,glow,.105,-.015,-.15);
    if(/silenc|suppress/i.test(attachments))tube(.06,.21,dark,0,.015,muzzleZ-.08);
    this.muzzle=new THREE.Object3D();this.muzzle.position.set(0,.015,muzzleZ-.08);group.add(this.muzzle);
    this.ejection=new THREE.Object3D();this.ejection.position.set(.1,.065,.03);group.add(this.ejection);
    const flashMaterial=new THREE.MeshBasicMaterial({color:config.color||'#f9d489',transparent:true,opacity:.9,depthWrite:false});this.ownedMaterials.push(flashMaterial);
    this.flash=add(new THREE.ConeGeometry(heavy||shotgun?.12:.075,.19,5),flashMaterial,0,.015,muzzleZ-.14);this.flash.rotation.x=-Math.PI/2;this.flash.visible=false;
    this.worldRoot.visible=false;
  }
  recoil(config){this.kick=Math.min(.15,this.kick+(config.recoil||.01)*(this.family==='smg'?3:4));this.flashTime=.04;this.inspection=0;}
  inspect(){this.inspection=1.5;}
  update(dt,{aiming=false,active,thirdPerson=false,reload,velocity=0,sprinting=false,reduceMotion=false,time=0}){
    this.root.visible=Boolean(active)&&!thirdPerson;this.worldRoot.visible=false;
    if(this.pendingConfig){this.holsterTime=Math.max(0,this.holsterTime-dt);if(this.holsterTime<=0)this.equip(this.pendingConfig,true);}
    this.kick*=Math.exp(-dt*(this.family==='heavy'||this.family==='sniper'?14:22));this.flashTime=Math.max(0,this.flashTime-dt);this.equipTime=Math.max(0,this.equipTime-dt);this.inspection=Math.max(0,this.inspection-dt);
    if(!this.body)return;
    this.ads+=(Number(aiming&&!reload)-this.ads)*Math.min(1,dt*(this.family==='sniper'?9:17));
    const progress=reload?THREE.MathUtils.clamp(1-reload.remaining/reload.total,0,1):0,tilt=reload?Math.sin(progress*Math.PI):0,empty=Boolean(reload?.empty||reload?.kind==='empty');
    const equip=this.pendingConfig?1-this.holsterTime/.09:this.equipTime/this.equipDuration,inspection=!reduceMotion&&this.inspection>0?Math.sin((1-this.inspection/1.5)*Math.PI):0;
    const bob=reduceMotion?0:Math.sin(time*9)*Math.min(velocity*.0013,.01)*(1-this.ads*.8),sprint=sprinting&&!aiming&&!reload?1:0;
    this.root.scale.setScalar(this.family==='heavy'?.66:.7);
    this.root.position.set(.35-this.ads*.25+inspection*.055,-.29+this.ads*.08-tilt*.12-equip*.27+bob,-.67+this.kick+equip*.16);
    this.root.rotation.set(this.kick*1.5+tilt*.22+equip*.7+sprint*.18,inspection*.7+sprint*.3,-tilt*.65+inspection*.55-sprint*.35);
    const magazineTravel=reload&&progress>.15&&progress<.77?Math.sin((progress-.15)/.62*Math.PI):0;
    this.magazine.position.y=-.16-magazineTravel*.22;this.magazine.rotation.z=magazineTravel*.18;
    this.magazine.visible=!(empty&&progress>.27&&progress<.48);
    this.bolt.position.z=.1+(this.kick> .002?this.kick*.9:0)+(empty&&progress>.82?Math.sin((progress-.82)/.18*Math.PI)*.06:0);
    this.pump.position.z=-.38+(this.family==='shotgun'?Math.min(.15,this.kick*2):0);
    this.flash.visible=this.flashTime>0;this.flash.rotation.z=time*43;
    this.reloadProgress=progress;
  }
  muzzlePosition(){this.root.updateWorldMatrix(true,true);return this.muzzle?.getWorldPosition(new THREE.Vector3())||this.camera.getWorldPosition(new THREE.Vector3());}
  shellPosition(){this.root.updateWorldMatrix(true,true);return this.root.visible?this.ejection?.getWorldPosition(new THREE.Vector3()):null;}
  dispose(){this.clear();this.root.removeFromParent();this.worldRoot.removeFromParent();}
}
