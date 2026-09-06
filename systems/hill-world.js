import * as THREE from 'three';

const PALETTE=['#b88669','#aebaac','#c3a965','#729791','#b87669','#7994a7'];
export const HILL_BOUNDS=Object.freeze({minX:-42,maxX:42,minZ:-56,maxZ:98,minY:0,maxY:20});
export const HILL_DISTRICTS=Object.freeze([
  {name:'Largo da Chegada',x:0,z:-39,y:0,radius:25},
  {name:'Cisterna Esquecida',x:-28,z:-7,y:0,radius:15},
  {name:'Escadaria do Varal',x:-11,z:-6,y:3,radius:14},
  {name:'Galeria Subterrânea',x:0,z:15,y:0,radius:17},
  {name:'Rua das Oficinas',x:18,z:18,y:6,radius:22},
  {name:'Beco das Mangueiras',x:-20,z:25,y:6,radius:22},
  {name:'Ladeira do Mirante',x:27,z:47,y:9,radius:15},
  {name:'Terraços do Vento',x:-23,z:65,y:12,radius:20},
  {name:'Pátio das Antenas',x:0,z:81,y:12,radius:23},
]);

function seeded(seed){let n=seed>>>0;return ()=>{n+=0x6D2B79F5;let t=Math.imul(n^n>>>15,1|n);t^=t+Math.imul(t^t>>>7,61|t);return ((t^t>>>14)>>>0)/4294967296;};}
const inside=(r,x,z)=>x>=r.x-r.width/2-.001&&x<=r.x+r.width/2+.001&&z>=r.z-r.depth/2-.001&&z<=r.z+r.depth/2+.001;

/**
 * Returns the reachable floor under feet at referenceY. Floors within 0.55 m above
 * feet are valid steps; a roof is NOT selected when walking through its interior.
 * Call with Infinity only when deliberately finding the uppermost spawn surface.
 * On leaving a roof the lower floor is returned, allowing player gravity to act.
 */
export function createSurfaceSampler(surfaces,{stepHeight=.55,fallback=0}={}){
  return (x,z,referenceY=0)=>{
    let reachable=-Infinity,lowest=Infinity;
    for(const surface of surfaces){if(!inside(surface,x,z))continue;const y=typeof surface.height==='function'?surface.height(x,z):surface.height;lowest=Math.min(lowest,y);if(y<=referenceY+stepHeight+.0001)reachable=Math.max(reachable,y);}
    return reachable!==-Infinity?reachable:lowest!==Infinity?lowest:fallback;
  };
}

export function createHillWorld({scene,colliders,seed=1}){
  const random=seeded(seed),group=new THREE.Group();group.name='Morro do Vento';scene.add(group);
  const surfaces=[],hitMeshes=[],interactions=[],doors=[],mapAreas=[],ownColliders=[],geometries=new Map(),materials=new Map(),textures=new Set(),boxBatches=new Map();
  const heightAt=createSurfaceSampler(surfaces);
  const material=(color,emissive=false)=>{const key=color+emissive;if(!materials.has(key))materials.set(key,new THREE.MeshStandardMaterial({color,roughness:.88,emissive:emissive?color:0,emissiveIntensity:emissive?.48:0}));return materials.get(key);};
  const geometry=(key,factory)=>{if(!geometries.has(key))geometries.set(key,factory());return geometries.get(key);};
  const cube=geometry('unit-box',()=>new THREE.BoxGeometry(1,1,1));
  const add=(geo,color,x,y,z,parent=group,emissive=false)=>{const mesh=new THREE.Mesh(geo,material(color,emissive));mesh.position.set(x,y,z);mesh.castShadow=true;mesh.receiveShadow=true;parent.add(mesh);return mesh;};
  const solid=(x,y,z,w,h,d,extra={})=>{const c={x,z,width:w,depth:d,minY:y-h/2,height:y+h/2,world:true,...extra};colliders.push(c);ownColliders.push(c);return c;};
  const box=(x,y,z,w,h,d,color,collision=false,parent=group)=>{
    if(collision)solid(x,y,z,w,h,d);
    if(parent===group){if(!boxBatches.has(color))boxBatches.set(color,[]);boxBatches.get(color).push(new THREE.Matrix4().compose(new THREE.Vector3(x,y,z),new THREE.Quaternion(),new THREE.Vector3(w,h,d)));return null;}
    const mesh=add(cube,color,x,y,z,parent);mesh.scale.set(w,h,d);return mesh;
  };
  const floor=(x,z,width,depth,height,color='#888d79',bottom=-1)=>{
    surfaces.push({x,z,width,depth,height});const thickness=Math.max(.18,height-bottom);
    box(x,height-thickness/2,z,width,thickness,depth,color,true);ownColliders.at(-1).surface=true;
    mapAreas.push({x,z,width,depth,height,color});
  };
  const platform=(x,z,w,d,y,bottom,color='#a5a088')=>floor(x,z,w,d,y,color,bottom);
  const stair=(x,z0,z1,w,y0,y1,color='#b2a890')=>{
    const steps=Math.ceil(Math.abs(y1-y0)/.3),d=(z1-z0)/steps;
    for(let i=0;i<steps;i++){const y=y0+(y1-y0)*(i+1)/steps,z=z0+(i+.5)*d;floor(x,z,w,d,y,color,y0-.35);box(x,y+.012,z+d/2-.04,w,.025,.07,'#d0c4a7');}
    mapAreas.push({x,z:(z0+z1)/2,width:w,depth:z1-z0,height:y1,color:'#c4b99b',type:'stairs',from:y0,to:y1});
  };
  const ramp=(x,z0,z1,w,y0,y1)=>{
    const vertices=new Float32Array([x-w/2,y0,z0,x+w/2,y0,z0,x-w/2,y1,z1,x+w/2,y0,z0,x+w/2,y1,z1,x-w/2,y1,z1]);
    const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.BufferAttribute(vertices,3));geo.computeVertexNormals();geometries.set(`ramp-${x}-${z0}`,geo);
    const mesh=add(geo,'#8c9183',0,0,0);mesh.material=material('#8c9183');mesh.material.side=THREE.DoubleSide;hitMeshes.push(mesh);
    surfaces.push({x,z:(z0+z1)/2,width:w,depth:z1-z0,height:(_x,z)=>y0+(y1-y0)*THREE.MathUtils.clamp((z-z0)/(z1-z0),0,1)});
    mapAreas.push({x,z:(z0+z1)/2,width:w,depth:z1-z0,height:y1,color:'#9da491',type:'ramp',from:y0,to:y1});
    for(const side of [-1,1]){const edge=new THREE.BufferGeometry();edge.setAttribute('position',new THREE.Float32BufferAttribute([x+side*w/2,y0-.3,z0,x+side*w/2,y1,z1,x+side*w/2,y0-.3,z1],3));edge.computeVertexNormals();geometries.set(`ramp-edge-${x}-${z0}-${side}`,edge);const m=add(edge,'#777f70',0,0,0);m.material.side=THREE.DoubleSide;hitMeshes.push(m);}
    for(let z=z0+1;z<z1;z+=3){const y=y0+(y1-y0)*(z-z0)/(z1-z0);box(x,y+.02,z,.13,.03,1.15,'#c9c6a9');}
  };
  const label=(text,x,y,z,w=4,color='#e9d7b2')=>{
    if(typeof document==='undefined')return null;
    const canvas=document.createElement('canvas');canvas.width=512;canvas.height=128;const ctx=canvas.getContext('2d');if(!ctx)return null;
    ctx.fillStyle='#203e44';ctx.fillRect(0,0,512,128);ctx.strokeStyle=color;ctx.lineWidth=5;ctx.strokeRect(7,7,498,114);ctx.fillStyle=color;ctx.textAlign='center';ctx.font='700 31px sans-serif';ctx.fillText(text,256,77,470);
    const texture=new THREE.CanvasTexture(canvas);texture.colorSpace=THREE.SRGBColorSpace;textures.add(texture);
    const mat=new THREE.SpriteMaterial({map:texture,depthTest:true,depthWrite:false});materials.set(`sign-${text}-${x}-${z}`,mat);
    const mesh=new THREE.Sprite(mat);mesh.scale.set(Math.min(w,3),Math.min(w,3)/4,1);mesh.position.set(x,y,z);group.add(mesh);return mesh;
  };
  const post=(x,y,z)=>{box(x,y+2.7,z,.1,5.4,.1,'#465d5a');box(x+.45,y+5.35,z,1,.12,.18,'#465d5a');box(x+.85,y+5.2,z,.42,.11,.35,'#efddaa');};
  const cable=(a,b,color='#3c4b49')=>{const mid=a.clone().lerp(b,.5);mid.y-=.65;const curve=new THREE.QuadraticBezierCurve3(a,mid,b),geo=new THREE.TubeGeometry(curve,10,.025,4,false);geometries.set(`cable-${geometries.size}`,geo);add(geo,color,0,0,0);};

  // Three built terraces. Their cuts reserve two independent ways uphill plus a
  // genuine lower passage beneath the middle street. Walls are actual volumes.
  floor(0,-36,84,40,0,'#919786');
  for(const [a,b,y]of [[-42,-40,6],[-40,-17,0],[-17,-14,6],[-8,-3,6],[3,16,6],[24,42,6]])floor((a+b)/2,-6,b-a,20,y,y?'#8d927e':'#777f73');
  stair(-11,-16,4,6,0,6);ramp(20,-16,4,8,0,6);
  floor(0,-6,6,20,0,'#66766e');platform(0,-4,6,16,6,3.4,'#9b9983');
  floor(-22.5,21,39,34,6,'#8c957e');floor(25.5,21,33,34,6,'#8c957e');
  floor(0,12,6,16,0,'#697a71');platform(0,12,6,16,6,3.4);
  floor(6,12,6,16,6,'#8c957e');floor(3,22,12,4,0,'#697a71');platform(3,22,12,4,6,3.4);
  floor(0,31,6,14,6,'#8c957e');stair(6,24,36,6,0,6,'#9fa48c');platform(6,37,6,2,6,5.75,'#9fa48c');
  for(const [a,b]of [[-42,-14],[-8,23],[31,42]])floor((a+b)/2,48,b-a,20,12,'#87917c');
  stair(-11,38,58,6,6,12);ramp(27,38,58,8,6,12);
  floor(0,78,84,40,12,'#8c967f');

  // Boundary parapets are visible and collidable; the silhouette continues into
  // decorative distant dwellings rather than an infinite flat procedural field.
  for(const side of [-1,1])for(let z=-51;z<98;z+=10){const y=heightAt(side*41,z,Infinity);box(side*42.6,y+1.1,z,1.2,2.2,10,'#687764',true);}
  box(0,1.05,-56.4,84,2.1,.8,'#7a8c81',true);box(0,13.1,98.4,84,2.2,.8,'#788873',true);

  function building(x,z,w,d,h,base,{interior=false,roof=false,index=0}={}){
    const color=PALETTE[(index+Math.floor(random()*3))%PALETTE.length],top=base+h;
    if(!interior)box(x,base+h/2,z,w,h,d,color,true);
    else{
      box(x-w/2+.16,base+h/2,z,.32,h,d,color,true);box(x+w/2-.16,base+h/2,z,.32,h,d,color,true);box(x,base+h/2,z+d/2-.16,w,h,.32,color,true);
      const half=(w-2.4)/2;for(const side of [-1,1])box(x+side*(1.2+half/2),base+h/2,z-d/2+.16,half,h,.32,color,true);
      box(x,base+h-.38,z-d/2+.16,2.4,.76,.32,color,true);
      box(x,base+.04,z,w-.6,.08,d-.6,'#b3a88d');
      box(x-w*.25,base+.4,z+d*.22,1.5,.8,.6,'#7d684f',true);
    }
    platform(x,z,w+.3,d+.3,top,top-.23,'#a6a68e');
    // Recessed-looking windows, contrasting frames, roof tanks and utility boxes.
    for(const side of [-1,1])for(let i=0;i<3;i++){
      const wx=x-w*.3+i*w*.3,wy=base+1.85;if(interior&&side<0&&i===1)continue;
      box(wx,wy,z+side*(d/2+.015),1.25,1.25,.08,'#ded2ac');box(wx,wy,z+side*(d/2+.065),1.03,1.03,.03,index%3?'#496469':'#8dbaac');
      box(wx,wy,z+side*(d/2+.09),.06,1.02,.045,'#b7bea4');
    }
    const tank=add(geometry('roof-tank',()=>new THREE.CylinderGeometry(.7,.75,1.1,10)),'#4e747f',x-w*.27,top+.55,z+d*.22);tank.castShadow=true;
    box(x+w*.25,top+.42,z+d*.2,.07,.85,.07,'#556359');box(x+w*.25,top+.84,z+d*.2,1.1,.035,.035,'#556359');
    if(roof){const stairX=x+w/2+1.4,z0=z-d/2-.8,z1=z+d/2-.5;stair(stairX,z0,z1,2.5,base,top);platform(x+w/2+.6,z1+.35,4.5,2,top,top-.22);box(x-w/2,top+.35,z,.14,.7,d,'#d4bfa0',true);}
    return {x,z,top};
  }
  let index=0;
  for(const z of [-44,-29])for(const x of [-31,-19,19,32])building(x,z,8,9,x===-19&&z===-29?3.8:3.5+random()*1.6,0,{interior:x===19&&z===-44,roof:x===-19&&z===-29,index:index++});
  for(const z of [11,28])for(const x of [-30,-19,18,33])building(x,z,8,10,3.5+random()*1.4,6,{interior:x===-19&&z===28,roof:x===18&&z===28,index:index++});
  for(const x of [-31,-21,20,32])building(x,64,7,8,3.4+random()*1.4,12,{interior:x===20,index:index++});
  for(const x of [-30,29])building(x,85,8,11,4+random(),12,{index:index++});
  for(const side of [-1,1])for(let i=0;i<12;i++){
    const x=side*(49+random()*12),z=-49+i*12,y=Math.max(0,(z+25)*.17)+2+random()*2,h=3+random()*3;
    box(x,y+h/2,z,6+random()*3,h,7+random()*3,PALETTE[i%PALETTE.length]);box(x,y+h+.13,z,7,.26,8,'#91a08b');
  }
  // Empty residential windows and shops are scenery. No civilian is a target.
  label('MORRO DO VENTO',0,3.8,-53,7);label('OFICINAS · MIRANTE →',12,9.3,5,6);label('GALERIA 03',0,2.5,-12.15,4);
  label('ESCADARIA DO VARAL',-11,3.6,-17.5,5);label('PÁTIO DAS ANTENAS',0,16.5,69,6);label('SAÍDA → OFICINAS',6,8.4,37.9,4.5);
  label('LARGO DA CHEGADA',0,3.4,-23,6);

  // Microareas: a breathing square, a compact market and ground-level street props.
  const paving=add(geometry('square',()=>new THREE.CircleGeometry(9,36)),'#baa98c',0,.025,-38);paving.rotation.x=-Math.PI/2;paving.castShadow=false;
  for(const [x,z,y]of [[-9,-41,0],[9,-41,0],[-9,-32,0],[10,17,6],[-7,30,6],[-18,61,12],[15,65,12]]){
    box(x,y+.4,z,1.8,.8,.7,'#77694f',true);box(x,y+.96,z+.27,1.8,.6,.11,'#a38962');
  }
  for(const [x,z,y]of [[-7,-47,0],[7,-47,0],[12,12,6],[12,21,6]]){
    box(x,y+.55,z,2.7,1.1,1.4,'#768b74',true);box(x,y+2.35,z,3.3,.16,2.2,index++%2?'#bd8c67':'#99b29b');
    for(const side of [-1,1])box(x+side*1.4,y+1.3,z,.08,2.3,.08,'#596957');
  }
  for(const [x,z,y]of [[-12,-48,0],[12,-24,0],[-15,6,6],[12,34,6],[-16,60,12],[15,96,12]])post(x,y,z);
  for(const [z,y]of [[-36,0],[18,6],[62,12]]){cable(new THREE.Vector3(-16,y+5.9,z),new THREE.Vector3(12,y+5.9,z+1));for(let i=0;i<6;i++)box(-10+i*3,y+5.1+Math.abs(i-2.5)*.06,z+.4,.85,.85,.035,PALETTE[i]);}
  for(const [x,z,y]of [[-37,-50,0],[37,-22,0],[-37,35,6],[37,34,6],[-37,62,12]]){
    add(geometry('trunk',()=>new THREE.CylinderGeometry(.16,.25,3.4,7)),'#765c43',x,y+1.7,z);solid(x,y+1.7,z,.5,3.4,.5);
    const crown=add(geometry('crown',()=>new THREE.IcosahedronGeometry(2,1)),index++%2?'#72875c':'#97a16c',x,y+3.9,z);crown.scale.y=.8;
  }
  // Door/gate collision uses the same array as movement, raycast and minimap.
  function gate(id,name,x,y,z,width,{closed=true,cost=0,unlockRound=1,boss=false}={}){
    const g=new THREE.Group();g.position.set(x,y,z);group.add(g);
    for(let offset=-width/2+.15;offset<width/2;offset+=.38)box(offset,1.55,0,.12,3.1,.2,boss?'#b27355':'#657d73',false,g);
    box(0,2.9,0,width,.15,.22,'#d0bb83',false,g);box(0,.38,0,width,.13,.22,'#b19d74',false,g);
    const c={x,z,width,depth:.3,minY:y,height:y+3.2,world:true,door:id};
    ownColliders.push(c);if(closed)colliders.push(c);g.visible=closed;
    const position=new THREE.Vector3(x,y,z-1.5),door={id,name,g,collider:c,closed,cost,unlockRound,boss,position};doors.push(door);
    if(!boss)interactions.push({id,type:'door',name,position:position.clone(),pos:position.clone(),cost,unlockRound,doorId:id,opened:!closed,g,mesh:g});
    return door;
  }
  gate('varal-shortcut','Abrir Escadaria do Varal',-11,0,-16.2,6,{cost:180,unlockRound:2});
  gate('gallery-vault','Cofre da Galeria',0,0,12,6,{cost:320,unlockRound:3});

  // Boss arenas have a single readable entrance; their combat gates are otherwise open.
  const bossZones=[];
  function arena({id,name,x,z,y,w,d,gateZ,unlockRound,archetype}){
    const gateId=`${id}-gate`;box(x-w/2,y+2,z,.5,4,d,'#69776e',true);box(x+w/2,y+2,z,.5,4,d,'#69776e',true);box(x,y+2,z+d/2,w,4,.5,'#69776e',true);
    const opening=6,side=(w-opening)/2;for(const sign of [-1,1])box(x+sign*(opening/2+side/2),y+2,gateZ,side,4,.5,'#69776e',true);
    gate(gateId,name,x,y,gateZ,opening,{closed:false,boss:true,unlockRound});
    const position=new THREE.Vector3(x,y,z),entry=new THREE.Vector3(x,y,gateZ-2);
    bossZones.push({id,name,position,center:position,radius:Math.min(w,d)/2-1,entry,unlockRound,archetype,gateId,gateIds:[gateId]});
    const ring=add(geometry(`arena-ring-${w}`,()=>new THREE.TorusGeometry(Math.min(w,d)/2-1.2,.09,5,48)),'#bead76',x,y+.055,z);ring.rotation.x=-Math.PI/2;ring.castShadow=false;
    mapAreas.push({x,z,width:w,depth:d,height:y,color:'#998276',type:'boss'});
  }
  arena({id:'summit',name:'Pátio das Antenas',x:0,z:82,y:12,w:27,d:24,gateZ:70,unlockRound:5,archetype:'conductor'});
  arena({id:'cistern',name:'Cisterna Esquecida',x:-28,z:-7,y:0,w:22,d:20,gateZ:-17,unlockRound:9,archetype:'furnace'});
  for(const side of [-1,1]){box(side*10,17,91,.5,10,.5,'#435953');for(let y=14;y<23;y+=1.5)box(side*10,y,91,2.3,.06,.08,'#9cae93');}
  label('CISTERNA · ACESSO RESTRITO',-28,3.7,-17.35,6);

  const markerGeometry=geometry('marker-diamond',()=>new THREE.OctahedronGeometry(.28));
  function marker(id,type,name,x,z,{y=heightAt(x,z,0),cost=0,unlockRound=1,...extra}={}){
    const color={chest:'#d3ad61',vault:'#b9a2de',shop:'#84bdab',forge:'#a491ce',challenge:'#d19373',quest:'#95bfc5'}[type]||'#d3ad61';
    const g=new THREE.Group();g.position.set(x,y,z);group.add(g);
    if(type==='chest'||type==='vault'){
      box(0,.34,0,1.1,.65,.72,'#576b61',false,g);box(0,.7,0,1.15,.15,.76,color,false,g);box(0,.38,-.4,.2,.22,.07,color,false,g);
      for(const side of [-1,1])box(side*.37,.43,0,.08,.73,.8,color,false,g);
    }else if(type==='forge'){
      box(0,.5,0,.8,1,.8,'#57675f',false,g);box(0,1.1,0,1.55,.25,.65,color,false,g);box(-.5,1.22,0,.55,.32,.65,'#d1c5e1',false,g);
    }else if(type==='shop'){
      box(0,.65,0,2,1.3,1.1,'#5f7e70',false,g);box(0,2.1,0,2.5,.16,1.7,color,false,g);for(const side of [-1,1])box(side*1.05,1.35,0,.08,1.5,.08,'#456555',false,g);
    }else{box(0,.38,0,.8,.75,.8,'#536d66',false,g);add(markerGeometry,color,0,1.05,0,g,true);}
    const diamond=add(markerGeometry,color,0,type==='shop'?2.65:1.6,0,g,true);diamond.rotation.z=Math.PI/4;
    const position=new THREE.Vector3(x,y,z),item={id,type,name,position,pos:position,cost,unlockRound,g,mesh:g,...extra};interactions.push(item);
    // The nearby interaction HUD supplies the name; diamonds and silhouettes
    // identify stations without giant signs covering the sight line.
    return item;
  }
  marker('arrival-cache','chest','Baú de boas-vindas',5,-37,{cost:0,lootTier:0});
  marker('street-shop','shop','Trocas do Largo',-6,-29,{cost:0});
  marker('arrival-forge','forge','Forja de Campo',7,-28,{cost:150});
  marker('roof-cache','chest','Reserva do Telhado',-20,-30,{y:3.8,lootTier:1,cost:100});
  marker('gallery-cache','vault','Cofre de Contrabando',0,19,{y:0,lootTier:2,cost:140,unlockRound:3,doorId:'gallery-vault'});
  marker('workshop-forge','forge','Bancada das Oficinas',13,32,{y:6,cost:220,unlockRound:3});
  marker('hidden-room','chest','Sala dos Mapas',-19,30,{y:6,lootTier:2,cost:160,unlockRound:4});
  marker('middle-shop','shop','Armeiro da Ladeira',35,20,{y:6,unlockRound:4});
  marker('defend-relay','challenge','Relé em Perigo',-6,9,{y:6,cost:0,unlockRound:3,challenge:'holdout'});
  marker('summit-trial','challenge','Prova do Mirante',14,62,{y:12,cost:150,unlockRound:6,challenge:'elite'});
  marker('summit-cache','chest','Baú do Mirante',-20,74,{y:12,cost:400,lootTier:3,unlockRound:7});
  marker('courier-job','quest','Entrega nas Alturas',4,-29,{cost:0,quest:'courier',target:new THREE.Vector3(14,12,63),reward:250});
  // Loot alcoves move among authored, navigable positions. Routes never randomize
  // into a softlock and no random obstacle is placed in the center of a passage.
  const secrets=[[-36,-35,0],[38,-41,0],[-35,18,6],[38,9,6],[-35,74,12],[37,76,12]];
  for(let i=0;i<3;i++){const slot=secrets.splice(Math.floor(random()*secrets.length),1)[0];marker(`secret-${i}`,'chest','Caixa Esquecida',slot[0],slot[1],{y:slot[2],cost:60+i*50,lootTier:i+1,secret:true});}
  const spawnPoints=[[-10,-51],[11,-49],[-11,-24],[11,-20],[20,-13],[20,3],[-11,5],[-7,17],[12,36],[-11,37],[27,38],[-11,60],[27,60],[-17,73],[17,73]].map(([x,z])=>new THREE.Vector3(x,heightAt(x,z,0),z));
  const world={
    seed,group,surfaces,hitMeshes,heightAt,spawn:new THREE.Vector3(0,0,-43),spawnPoints,interactions,bossZones,doors,bounds:{...HILL_BOUNDS},mapAreas,districts:HILL_DISTRICTS,
    district(position){
      if(position.y<3&&position.z>-12&&position.z<26&&position.x>-4&&position.x<10)return 'Galeria Subterrânea';
      return HILL_DISTRICTS.reduce((best,d)=>{const distance=Math.hypot(position.x-d.x,position.z-d.z)+(Math.abs(position.y-d.y)>3?24:0);return distance<best.distance?{distance,name:d.name}:best;},{distance:Infinity,name:'Morro do Vento'}).name;
    },
    setGate(id,closed){const door=doors.find(d=>d.id===id);if(!door)return false;door.closed=!!closed;door.g.visible=!!closed;const index=colliders.indexOf(door.collider);if(closed&&index<0)colliders.push(door.collider);if(!closed&&index>=0)colliders.splice(index,1);colliders.revision=(colliders.revision||0)+1;for(const item of interactions)if(item.id===id)item.opened=!closed;return true;},
    openDoor(id){return world.setGate(id,false);},
    dispose(){group.removeFromParent();group.traverse(mesh=>{if(mesh.isInstancedMesh)mesh.dispose();});for(const collider of ownColliders){const index=colliders.indexOf(collider);if(index>=0)colliders.splice(index,1);}for(const geo of geometries.values())geo.dispose();for(const mat of materials.values())mat.dispose();for(const texture of textures)texture.dispose();},
  };
  // Static architecture shares draw calls by material. Animated gates and loot
  // keep independent groups so opening a door never alters its neighbors.
  for(const [color,matrices]of boxBatches){const mesh=new THREE.InstancedMesh(cube,material(color),matrices.length);matrices.forEach((matrix,index)=>mesh.setMatrixAt(index,matrix));mesh.instanceMatrix.needsUpdate=true;mesh.computeBoundingSphere();mesh.castShadow=true;mesh.receiveShadow=true;group.add(mesh);}
  group.updateMatrixWorld(true);
  return world;
}
