import * as THREE from 'three';

// Feet are the entity origin. Colliders use absolute minY / height, including ceilings.
// Surface sampling, collision and A* share the same step/drop limits.
export class Navigation {
  constructor(colliders,{heightAt=null,cell=heightAt?1:1.8,maxStep=.56,maxDrop=.8,actorHeight=1.55}={}){
    Object.assign(this,{colliders,cell,maxStep,maxDrop,actorHeight});this.terrainHeight=heightAt;
    this.heightAt=heightAt||((_x,_z,y=0)=>y);this.routes=new Map();
  }
  // Optional frame boundary used by the runtime. At most one expensive search
  // runs per frame; direct pursuit and already planned routes remain immediate.
  beginFrame(){this.frameManaged=true;this.replansThisFrame=0;}
  blocked(x,z,radius=.45,y=0,actorHeight=this.actorHeight){
    if(this.indexCount!==this.colliders.length||this.indexRevision!==(this.colliders.revision||0))this.indexColliders();
    const candidates=radius<=2?(this.spatial.get(`${Math.floor(x/8)},${Math.floor(z/8)}`)||[]):this.colliders;
    return candidates.some(c=>!c.disabled&&!c.prop?.userData.broken&&(!c.surface||c.height>y+this.maxStep)&&y+.09<(c.height??99)&&y+actorHeight>(c.minY??0)+.02&&Math.abs(x-c.x)<c.width/2+radius&&Math.abs(z-c.z)<c.depth/2+radius);
  }
  indexColliders(){
    this.spatial=new Map();this.indexCount=this.colliders.length;this.indexRevision=this.colliders.revision||0;
    for(const c of this.colliders){for(let x=Math.floor((c.x-c.width/2-2)/8);x<=Math.floor((c.x+c.width/2+2)/8);x++)for(let z=Math.floor((c.z-c.depth/2-2)/8);z<=Math.floor((c.z+c.depth/2+2)/8);z++){const key=`${x},${z}`;if(!this.spatial.has(key))this.spatial.set(key,[]);this.spatial.get(key).push(c);}}
  }
  step(from,x,z,radius=.45){
    const y=this.heightAt(x,z,from.y),rise=y-from.y;
    if(!Number.isFinite(y)||rise>this.maxStep||rise < -this.maxDrop||this.blocked(x,z,radius,y))return null;
    return new THREE.Vector3(x,y,z);
  }
  walkSegment(from,to,radius=.45){
    const distance=Math.hypot(to.x-from.x,to.z-from.z),steps=Math.max(1,Math.ceil(distance/.28));let point=from.clone();
    for(let i=1;i<=steps;i++){const t=i/steps,next=this.step(point,from.x+(to.x-from.x)*t,from.z+(to.z-from.z)*t,radius);if(!next)return null;point=next;}
    return point;
  }
  clearLine(from,to,radius=.45){const end=this.walkSegment(from,to,radius);return !!end&&Math.abs(end.y-to.y)<=this.maxStep;}
  freePosition(position,radius=.6){
    position.y=this.heightAt(position.x,position.z,position.y);
    if(!this.blocked(position.x,position.z,radius,position.y))return position;
    for(let r=.8;r<=24;r+=.8)for(let i=0;i<24;i++){
      const angle=i/24*Math.PI*2,x=position.x+Math.cos(angle)*r,z=position.z+Math.sin(angle)*r,y=this.heightAt(x,z,position.y);
      if(Number.isFinite(y)&&!this.blocked(x,z,radius,y))return position.set(x,y,z);
    }
    return position;
  }
  path(from,to,radius=.45){
    if(this.clearLine(from,to,radius))return [to.clone()];
    const revision=`${this.colliders.length}:${this.colliders.revision||0}`;
    if(this.routeRevision!==revision){this.routes.clear();this.routeRevision=revision;}
    const bucket=p=>`${Math.round(p.x/4)},${Math.round(p.y*2)},${Math.round(p.z/4)}`,routeKey=`${bucket(from)}>${bucket(to)}:${Math.ceil(radius*10)}`,cached=this.routes.get(routeKey);
    if(cached){
      let join=-1;for(let i=0;i<Math.min(cached.length,9);i++)if(this.clearLine(from,cached[i],radius)){join=i;break;}
      if(join>=0&&this.clearLine(cached.at(-1),to,radius)){const result=cached.slice(join).map(p=>p.clone());if(result.at(-1).distanceToSquared(to)<.0025)result[result.length-1]=to.clone();else result.push(to.clone());return result;}
    }
    const cell=this.cell,sx=Math.round(from.x/cell),sz=Math.round(from.z/cell),gx=Math.round(to.x/cell),gz=Math.round(to.z/cell);
    const startPosition=this.walkSegment(from,new THREE.Vector3(sx*cell,from.y,sz*cell),radius)||from.clone();
    const key=(x,z,y)=>`${x},${z},${Math.round(y*4)}`,start={x:sx,z:sz,y:startPosition.y,g:0,f:0,parent:null},open=new MinHeap(),best=new Map([[key(sx,sz,start.y),0]]),closed=new Set();open.push(start);
    const directions=[[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]];
    let nearest=start,nearestDistance=Infinity;
    const margin=25,minX=Math.min(sx,gx)-margin,maxX=Math.max(sx,gx)+margin,minZ=Math.min(sz,gz)-margin,maxZ=Math.max(sz,gz)+margin;
    for(let visited=0;open.length&&visited<6500;visited++){
      const current=open.pop(),currentKey=key(current.x,current.z,current.y);if(closed.has(currentKey))continue;closed.add(currentKey);
      const currentPosition=new THREE.Vector3(current.x*cell,current.y,current.z*cell),h=Math.hypot(gx-current.x,gz-current.z)+Math.abs(to.y-current.y)*.8;
      if(h<nearestDistance){nearestDistance=h;nearest=current;}
      if(Math.hypot(gx-current.x,gz-current.z)<1.2&&this.clearLine(currentPosition,to,radius)){nearest=current;break;}
      for(const [dx,dz]of directions){
        const x=current.x+dx,z=current.z+dz;if(x<minX||x>maxX||z<minZ||z>maxZ)continue;
        const next=this.walkSegment(currentPosition,new THREE.Vector3(x*cell,current.y,z*cell),radius);if(!next)continue;
        if(dx&&dz&&(!this.walkSegment(currentPosition,new THREE.Vector3(x*cell,current.y,current.z*cell),radius)||!this.walkSegment(currentPosition,new THREE.Vector3(current.x*cell,current.y,z*cell),radius)))continue;
        const k=key(x,z,next.y),g=current.g+(dx&&dz?1.414:1)+Math.abs(next.y-current.y)*.16;if(closed.has(k)||(best.get(k)??Infinity)<=g)continue;
        best.set(k,g);open.push({x,z,y:next.y,g,f:g+Math.hypot(gx-x,gz-z)+Math.abs(to.y-next.y)*.8,parent:current});
      }
    }
    const result=[];for(let node=nearest;node.parent;node=node.parent)result.unshift(new THREE.Vector3(node.x*cell,node.y,node.z*cell));
    if(result.length&&this.clearLine(result.at(-1),to,radius)){
      result.push(to.clone());this.routes.set(routeKey,result.map(p=>p.clone()));if(this.routes.size>128)this.routes.delete(this.routes.keys().next().value);
    }
    return result;
  }
  move(entity,target,speed,dt,radius=.45){
    const position=entity.g.position;entity.navTimer=(entity.navTimer||0)-dt;
    const goalChanged=!entity.navGoal||entity.navGoal.distanceToSquared(target)>16;
    if(entity.navTimer<=0||!entity.path||goalChanged){
      const direct=this.clearLine(position,target,radius);
      if(direct||!this.frameManaged||this.replansThisFrame<1){
        if(!direct)this.replansThisFrame++;
        entity.path=direct?[target.clone()]:this.path(position,target,radius);entity.navGoal=target.clone();entity.navTimer=4+(Math.abs(entity.seed||0)%5)*.24;
      }
    }
    let next=entity.path?.[0];while(next&&Math.hypot(next.x-position.x,next.z-position.z)<.25&&Math.abs(next.y-position.y)<.6){entity.path.shift();next=entity.path[0];}
    if(!next&&this.clearLine(position,target,radius))next=target;
    const before=position.clone();
    if(next){
      const direction=next.clone().sub(position),distance=direction.length();
      if(distance>.025){direction.multiplyScalar(Math.min(distance,Math.max(0,speed*dt))/distance);const steps=Math.max(1,Math.ceil(direction.length()/.22));
        for(let i=0;i<steps;i++){
          const x=position.x+direction.x/steps,z=position.z+direction.z/steps,point=this.step(position,x,z,radius);
          if(point)position.copy(point);
          else {const sideX=this.step(position,x,position.z,radius),sideZ=this.step(position,position.x,z,radius);if(sideX)position.copy(sideX);else if(sideZ)position.copy(sideZ);entity.navTimer=Math.min(entity.navTimer,.12);}
        }
      }
    }
    const velocity=position.clone().sub(before).multiplyScalar(1/Math.max(.001,dt));
    entity.velocity??=new THREE.Vector3();entity.velocity.lerp(velocity,1-Math.exp(-dt*15));
    entity.groundSlope=THREE.MathUtils.clamp(Math.atan2(velocity.y,Math.hypot(velocity.x,velocity.z)||1),-.45,.45);
    if(Math.hypot(entity.velocity.x,entity.velocity.z)>.28){const angle=Math.atan2(entity.velocity.x,entity.velocity.z),delta=THREE.MathUtils.euclideanModulo(angle-entity.g.rotation.y+Math.PI,Math.PI*2)-Math.PI;entity.turnRate=delta;entity.g.rotation.y+=delta*Math.min(1,dt*12);}
    return velocity.length();
  }
}

class MinHeap {
  constructor(){this.nodes=[];}get length(){return this.nodes.length;}
  push(value){const a=this.nodes;let i=a.length;a.push(value);while(i){const p=(i-1)>>1;if(a[p].f<=value.f)break;a[i]=a[p];i=p;}a[i]=value;}
  pop(){const a=this.nodes,first=a[0],last=a.pop();if(a.length){let i=0;while(true){let child=i*2+1;if(child>=a.length)break;if(child+1<a.length&&a[child+1].f<a[child].f)child++;if(a[child].f>=last.f)break;a[i]=a[child];i=child;}a[i]=last;}return first;}
}
