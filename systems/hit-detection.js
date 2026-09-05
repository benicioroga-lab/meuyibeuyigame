import * as THREE from 'three';

const scratchBox=new THREE.Box3(),scratchPoint=new THREE.Vector3(),normal=new THREE.Vector3();
function visible(mesh){for(let current=mesh;current;current=current.parent)if(!current.visible)return false;return true;}

export class HitWorld {
  constructor({colliders,props,enemies,getBoss=()=>null}){Object.assign(this,{colliders,props,enemies,getBoss});this.raycaster=new THREE.Raycaster();}
  surfaces(origin,direction,range,{props=true,padding=0}={}){
    const ray=new THREE.Ray(origin,direction);let closest=null;
    const accept=(distance,point,entity,kind,hitNormal)=>{if(distance>=0&&distance<=range&&(!closest||distance<closest.distance)){closest={distance,point:point.clone(),entity,kind,normal:hitNormal.clone()};}};
    for(const c of this.colliders){
      if(c.prop?.userData.broken||c.prop)continue; // Props use their real meshes below.
      scratchBox.min.set(c.x-c.width/2-padding,(c.minY||0)-padding,c.z-c.depth/2-padding);
      scratchBox.max.set(c.x+c.width/2+padding,c.height+padding,c.z+c.depth/2+padding);
      if(scratchBox.containsPoint(origin)){accept(0,origin,c,'wall',direction.clone().negate());continue;}
      if(!ray.intersectBox(scratchBox,scratchPoint))continue;
      normal.set(0,0,0);const p=scratchPoint,eps=.002;
      if(Math.abs(p.x-scratchBox.min.x)<eps)normal.x=-1;else if(Math.abs(p.x-scratchBox.max.x)<eps)normal.x=1;
      else if(Math.abs(p.y-scratchBox.max.y)<eps)normal.y=1;else if(Math.abs(p.y-scratchBox.min.y)<eps)normal.y=-1;
      else normal.z=Math.abs(p.z-scratchBox.min.z)<eps?-1:1;
      accept(origin.distanceTo(p),p,c,'wall',normal);
    }
    if(direction.y<-.00001){const distance=-origin.y/direction.y;accept(distance,origin.clone().addScaledVector(direction,distance),null,'wall',new THREE.Vector3(0,1,0));}
    if(props){
      this.raycaster.set(origin,direction);this.raycaster.near=0;this.raycaster.far=closest?closest.distance:range;
      for(const prop of this.props){
        if(prop.userData.broken||!prop.parent)continue;
        prop.updateWorldMatrix(true,true);
        prop.userData.shotBounds??=new THREE.Box3().setFromObject(prop);
        if(!ray.intersectsBox(prop.userData.shotBounds))continue;
        const intersections=this.raycaster.intersectObject(prop,true);
        const hit=intersections.find(hit=>visible(hit.object));
        if(hit){const hitNormal=hit.face?.normal.clone().transformDirection(hit.object.matrixWorld)||direction.clone().negate();accept(hit.distance,hit.point,prop,'object',hitNormal);}
      }
    }
    return closest;
  }
  cast(origin,direction,range,{pierce=1,worldOnly=false,padding=0}={}){
    const cover=this.surfaces(origin,direction,range,{padding});
    if(worldOnly)return cover?[cover]:[];
    const maximum=cover?cover.distance:range,ray=new THREE.Ray(origin,direction),hits=[];
    this.raycaster.set(origin,direction);this.raycaster.near=0;this.raycaster.far=maximum;
    for(const enemy of this.enemies){
      if(enemy.disabled||!enemy.g.parent)continue;
      const s=enemy.config?.scale||1;
      scratchBox.setFromCenterAndSize(enemy.g.position.clone().add(new THREE.Vector3(0,1.2*s,0)),new THREE.Vector3(2.7*s,3*s,2.7*s));
      if(!ray.intersectsBox(scratchBox))continue;
      enemy.g.updateWorldMatrix(true,true);
      const hit=this.raycaster.intersectObjects(enemy.hitMeshes,false)[0];
      if(hit)hits.push({kind:'enemy',entity:enemy,zone:hit.object.userData.zone||'body',point:hit.point.clone(),distance:hit.distance,normal:hit.face.normal.clone().transformDirection(hit.object.matrixWorld)});
    }
    const boss=this.getBoss();
    if(boss?.active&&!boss.defeated){boss.g.updateWorldMatrix(true,true);const hit=this.raycaster.intersectObject(boss.g,true).find(hit=>visible(hit.object)&&hit.object!==boss.aura);if(hit)hits.push({kind:'boss',entity:boss,zone:'body',point:hit.point.clone(),distance:hit.distance,normal:direction.clone().negate()});}
    hits.sort((a,b)=>a.distance-b.distance);
    const selected=hits.slice(0,pierce);
    if(selected.length<pierce&&cover)selected.push(cover);
    return selected;
  }
  aim(camera,muzzle,config,random=Math.random){
    const direction=new THREE.Vector3();camera.getWorldDirection(direction);
    if(config.spread>0){const right=new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld,0),up=new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld,1);const angle=random()*Math.PI*2,radius=Math.sqrt(random())*config.spread;direction.addScaledVector(right,Math.cos(angle)*radius).addScaledVector(up,Math.sin(angle)*radius).normalize();}
    const hits=this.cast(camera.position,direction,config.range,{pierce:config.pierce||1});
    const aimPoint=hits[0]?.point||camera.position.clone().addScaledVector(direction,config.range);
    // Camera decides the target. A second, world-only ray prevents firing around cover from the muzzle.
    const muzzleDirection=aimPoint.clone().sub(muzzle),distance=muzzleDirection.length();muzzleDirection.normalize();
    const obstruction=this.surfaces(muzzle,muzzleDirection,Math.max(0,distance-.035));
    if(obstruction)return {hits:[obstruction],point:obstruction.point,direction,muzzle,blocked:true};
    return {hits,point:hits.at(-1)?.point||aimPoint,direction,muzzle,blocked:false};
  }
  lineOfSight(from,to){const dir=to.clone().sub(from),distance=dir.length();if(distance<.01)return true;dir.normalize();return !this.surfaces(from,dir,Math.max(0,distance-.1));}
}
