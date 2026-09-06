import * as THREE from 'three';
import {FBXLoader} from 'https://cdn.jsdelivr.net/npm/three@0.160.1/examples/jsm/loaders/FBXLoader.js';

export function createHero(scene,player,onLoaded=()=>{}){
  const root=new THREE.Group(),fallback=new THREE.Group(),parts={legs:[]};root.add(fallback);root.position.copy(player.pos);scene.add(root);
  const fur=new THREE.MeshStandardMaterial({color:'#78412a',roughness:.8}),dark=new THREE.MeshStandardMaterial({color:'#352a23'}),cream=new THREE.MeshStandardMaterial({color:'#ca8d55'});
  const add=(geometry,material,x,y,z,parent=fallback)=>{const mesh=new THREE.Mesh(geometry,material);mesh.position.set(x,y,z);mesh.castShadow=true;parent.add(mesh);return mesh;};
  parts.body=add(new THREE.CapsuleGeometry(.4,.95,5,12),fur,0,.56,0);parts.body.rotation.x=Math.PI/2;
  parts.head=add(new THREE.SphereGeometry(.37,12,8),fur,0,.83,-.78);add(new THREE.SphereGeometry(.25,10,7),cream,0,.7,-1.05).scale.set(1,.7,1.3);add(new THREE.SphereGeometry(.09,8,6),dark,0,.76,-1.32);
  for(const side of [-1,1]){add(new THREE.SphereGeometry(.055,8,6),dark,side*.21,.93,-1.03);parts['ear'+(side<0?0:1)]=add(new THREE.CapsuleGeometry(.11,.32,4,8),dark,side*.34,.65,-.7);}
  for(const x of [-.28,.28])for(const z of [-.5,.5])parts.legs.push(add(new THREE.CapsuleGeometry(.1,.24,4,8),fur,x,.2,z));
  parts.tail=add(new THREE.CapsuleGeometry(.055,.4,4,8),dark,0,.68,.83);parts.tail.rotation.x=.6;
  const textures=new THREE.TextureLoader(),base=textures.load('assets/meyui/dachshunddog3dmodel_basecolor.jpeg');base.colorSpace=THREE.SRGBColorSpace;
  const material=new THREE.MeshStandardMaterial({map:base,normalMap:textures.load('assets/meyui/dachshunddog3dmodel_normal.jpeg'),roughnessMap:textures.load('assets/meyui/dachshunddog3dmodel_roughness.jpeg'),roughness:.82});
  new FBXLoader().load('assets/meyui/dachshund+dog+3d+model.fbx',model=>{
    const raw=new THREE.Box3().setFromObject(model).getSize(new THREE.Vector3());model.scale.setScalar(2.8/Math.max(raw.x,raw.y,raw.z));model.traverse(node=>{if(node.isMesh){node.material=material;node.castShadow=true;node.receiveShadow=true;}});model.updateMatrixWorld(true);
    const box=new THREE.Box3().setFromObject(model),center=box.getCenter(new THREE.Vector3());model.position.set(-center.x,-box.min.y,-center.z);model.rotation.y=Math.PI/2;parts.imported=model;parts.importBaseY=model.position.y;fallback.visible=false;root.add(model);onLoaded();
  },undefined,()=>onLoaded());
  return {root,parts,update(dt,time,speed){root.position.copy(player.pos);root.rotation.y=player.dir+Math.PI;const gait=Math.sin(time*Math.max(2,speed)*3.2);parts.legs.forEach((leg,i)=>leg.rotation.x=speed>.2?Math.sin(time*speed*3.2+(i%2)*Math.PI)*.5:0);parts.tail.rotation.z=Math.sin(time*7)*.25;if(parts.imported){parts.imported.position.y=parts.importBaseY+(speed>.2?Math.abs(gait)*.03:0);parts.imported.rotation.z=speed>.2?gait*.025:0;}}};
}
