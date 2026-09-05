import * as THREE from 'three';

export const DISTRICTS=[
  {name:'Praia do Petisco',x:-12,z:10,radius:24},
  {name:'Praça do Coreto',x:-2,z:-30,radius:15},
  {name:'Mercado dos Sabores',x:17,z:18,radius:17},
  {name:'Garagem da Sucata',x:36,z:-34,radius:19},
  {name:'Jardim dos Ipês',x:7,z:51,radius:15},
  {name:'Viela da Lavanderia',x:55,z:7,radius:15},
  {name:'Quadra do Au',x:37,z:45,radius:15},
  {name:'Morro do Mistério',x:82,z:8,radius:27},
];
export function seededRandom(seed){let value=seed>>>0;return ()=>{value+=0x6D2B79F5;let t=Math.imul(value^value>>>15,1|value);t^=t+Math.imul(t^t>>>7,61|t);return ((t^t>>>14)>>>0)/4294967296;};}

export function addWorldDetails(scene,colliders,seed){
  const random=seededRandom(seed),group=new THREE.Group(),materials=new Map();scene.add(group);
  const material=color=>{if(!materials.has(color))materials.set(color,new THREE.MeshStandardMaterial({color,roughness:.9}));return materials.get(color);};
  const add=(geo,color,x,y,z)=>{const mesh=new THREE.Mesh(geo,material(color));mesh.position.set(x,y,z);mesh.castShadow=true;mesh.receiveShadow=true;group.add(mesh);return mesh;};
  const block=(x,z,w,d,h)=>colliders.push({x,z,width:w,depth:d,height:h,detail:true});
  const box=(x,y,z,w,h,d,color,solid=false)=>{const mesh=add(new THREE.BoxGeometry(w,h,d),color,x,y,z);if(solid)block(x,z,w,d,y+h/2);return mesh;};
  const floor=(x,z,w,d,color)=>{const m=add(new THREE.PlaneGeometry(w,d),color,x,.145,z);m.rotation.x=-Math.PI/2;m.castShadow=false;return m;};
  function sign(x,z,text,color='#e7ce97'){
    const canvas=document.createElement('canvas');canvas.width=512;canvas.height=128;const ctx=canvas.getContext('2d');ctx.fillStyle='#263e45';ctx.fillRect(0,0,512,128);ctx.strokeStyle=color;ctx.lineWidth=5;ctx.strokeRect(8,8,496,112);ctx.fillStyle=color;ctx.font='bold 34px sans-serif';ctx.textAlign='center';ctx.fillText(text,256,78);const texture=new THREE.CanvasTexture(canvas);texture.colorSpace=THREE.SRGBColorSpace;
    const mesh=new THREE.Mesh(new THREE.PlaneGeometry(4,.95),new THREE.MeshStandardMaterial({map:texture,side:THREE.DoubleSide}));mesh.position.set(x,3,z);group.add(mesh);box(x-1.7,1.45,z,.08,2.9,.08,'#6c6353');box(x+1.7,1.45,z,.08,2.9,.08,'#6c6353');
  }
  function bench(x,z,angle=0){const bench=new THREE.Group();bench.position.set(x,0,z);bench.rotation.y=angle;group.add(bench);const parts=[[0,.48,0,2.1,.16,.65,'#967053'],[0,.9,-.27,2.1,.7,.12,'#967053'],[-.75,.24,0,.1,.48,.5,'#3e5558'],[.75,.24,0,.1,.48,.5,'#3e5558']];for(const [px,py,pz,w,h,d,color]of parts){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),material(color));m.position.set(px,py,pz);m.castShadow=true;bench.add(m);}block(x,z,angle? .8:2.1,angle?2.1:.8,1.3);}
  function tree(x,z,color){add(new THREE.CylinderGeometry(.17,.25,2.9,7),'#81614a',x,1.45,z);for(let i=0;i<4;i++){const crown=add(new THREE.SphereGeometry(1.05+random()*.25,8,6),color,x+Math.cos(i*2)*.55,3+random()*.6,z+Math.sin(i*2)*.55);crown.scale.y=.8;}block(x,z,.5,.5,2.8);}
  function car(x,z,color,angle=0){const car=new THREE.Group();car.position.set(x,0,z);car.rotation.y=angle;group.add(car);const parts=[[0,.65,0,2,.65,4,color],[0,1.15,-.25,1.65,.7,1.9,color],[0,1.25,.65,1.55,.45,.08,'#8da5a5']];for(const [px,py,pz,w,h,d,c]of parts){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),material(c));m.position.set(px,py,pz);m.castShadow=true;car.add(m);}for(const x of [-1,1])for(const z of [-1.25,1.25]){const wheel=new THREE.Mesh(new THREE.CylinderGeometry(.36,.36,.2,10),material('#303839'));wheel.rotation.z=Math.PI/2;wheel.position.set(x,.35,z);car.add(wheel);}block(x,z,angle?4:2,angle?2:4,1.5);}
  // A quiet square: circular paving, a readable central fountain and paths around it.
  const plaza=add(new THREE.CircleGeometry(12,40),'#c2b69a',-2,.15,-30);plaza.rotation.x=-Math.PI/2;plaza.castShadow=false;
  add(new THREE.CylinderGeometry(2.4,2.6,.5,18),'#849e9a',-2,.35,-30);add(new THREE.CylinderGeometry(1.9,1.9,.08,18),'#77a9b1',-2,.63,-30);add(new THREE.CylinderGeometry(.35,.65,1.8,10),'#c4bd9e',-2,1.2,-30);block(-2,-30,5,5,2.2);
  for(const [x,z,angle]of[[-10,-30,Math.PI/2],[6,-30,Math.PI/2],[-2,-39,0]])bench(x,z,angle);sign(-2,-20,'PRAÇA DO CORETO');
  // Food market: different awnings, goods and narrow but passable aisles.
  floor(17,18,13,19,'#aa9876');
  const stallColors=['#bd765e','#6c948c','#bdab63'];
  for(let i=0;i<3;i++){
    const x=i%2?21:13,z=12+i*6,color=stallColors[i];box(x,.7,z,2.5,1.4,1.45,color,true);box(x,2.15,z,3.2,.15,2.2,'#e0c99b');
    for(const side of[-1,1])box(x+side*1.3,1.45,z,.07,2,.07,'#6b6452');
    for(let fruit=0;fruit<7;fruit++)add(new THREE.SphereGeometry(.16,6,4),fruit%2?'#ceb563':'#b77752',x-.9+fruit*.29,1.53,z);
  }
  sign(17,29,'MERCADO DOS SABORES');
  // Garage / rubble: broad lanes, parked cars and cover with distinct silhouettes.
  floor(36,-34,19,25,'#6b726d');car(30,-34,'#a27361');car(42,-40,'#809591',Math.PI/2);car(43,-27,'#b69d5e');
  box(28,1.4,-44,3,2.8,5,'#8a6959',true);box(45,1.15,-44,3,2.3,4,'#727f79',true);
  for(let i=0;i<7;i++){const x=33+random()*6,z=-45+random()*4;box(x,.2,z,.5+random(),.4,.55,'#979285',true).rotation.y=random()*.4;}
  sign(36,-20,'GARAGEM DA SUCATA');
  // Flowering grove and a court give the southern edge a different color and rhythm.
  floor(5,50,21,20,'#798c67');for(const [x,z]of[[-2,46],[0,56],[11,57],[14,47]])tree(x,z,random()>.5?'#c79aac':'#c4b775');bench(6,53);sign(6,40,'JARDIM DOS IPÊS');
  floor(37,45,17,23,'#587f7c');floor(37,45,15,21,'#a97562');
  for(const x of[30,44])box(x,.17,45,.12,.035,19,'#e5d8b0');for(const z of[35.5,54.5,45])box(37,.17,z,14,.035,.12,'#e5d8b0');
  const circle=add(new THREE.TorusGeometry(2,.035,4,24),'#e5d8b0',37,.18,45);circle.rotation.x=Math.PI/2;circle.castShadow=false;
  for(const z of[35,55]){box(37,1,z,.08,2,.08,'#d1cdb7');box(35.6,1,z,.08,2,.08,'#d1cdb7');box(36.3,2,z,1.5,.08,.08,'#d1cdb7');}sign(37,59,'QUADRA DO AU');
  // An alley landmark without blocking its entrances.
  floor(55,7,20,5.5,'#a39c89');for(let i=0;i<8;i++){const x=48+i*2;box(x,4.9,7,.8,.8,.035,['#c39385','#b7c7b1','#c3b777'][i%3]);}box(55,5.45,7,18,.025,.025,'#35464b');sign(55,11,'VIELA DA LAVANDERIA');
  // Small seeded details vary between runs but keep the spawn and route centers clear.
  for(let i=0;i<15;i++){const x=10+random()*6,z=-52+random()*110;if(Math.abs(z-18)<13||Math.abs(z-50)<12)continue;add(new THREE.CylinderGeometry(.24,.3,.7,8),'#647e73',x,.35,z);block(x,z,.6,.6,.8);}
  return {group,district(position){const candidates=DISTRICTS.filter(d=>Math.hypot(d.x-position.x,d.z-position.z)<d.radius);return candidates.sort((a,b)=>Math.hypot(a.x-position.x,a.z-position.z)/a.radius-Math.hypot(b.x-position.x,b.z-position.z)/b.radius)[0]?.name||'Ruas da Confusão';}};
}
