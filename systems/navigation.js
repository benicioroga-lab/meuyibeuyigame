import * as THREE from 'three';

export class Navigation {
  constructor(colliders){this.colliders=colliders;this.cell=1.8;}
  blocked(x,z,radius=.45,y=.1){return this.colliders.some(c=>y<(c.height??99)&&Math.abs(x-c.x)<c.width/2+radius&&Math.abs(z-c.z)<c.depth/2+radius);}
  clearLine(from,to,radius=.45){const distance=Math.hypot(to.x-from.x,to.z-from.z),steps=Math.max(1,Math.ceil(distance/.65));for(let i=1;i<=steps;i++){const t=i/steps;if(this.blocked(from.x+(to.x-from.x)*t,from.z+(to.z-from.z)*t,radius,from.y))return false;}return true;}
  freePosition(position,radius=.6){
    if(!this.blocked(position.x,position.z,radius,position.y))return position;
    for(let r=1;r<=18;r++)for(let i=0;i<16;i++){const angle=i/16*Math.PI*2,x=position.x+Math.cos(angle)*r,z=position.z+Math.sin(angle)*r;if(!this.blocked(x,z,radius,position.y))return position.set(x,position.y,z);}
    return position;
  }
  path(from,to,radius=.45){
    if(this.clearLine(from,to,radius))return [to.clone()];
    const cell=this.cell,sx=Math.round(from.x/cell),sz=Math.round(from.z/cell),gx=Math.round(to.x/cell),gz=Math.round(to.z/cell);
    const key=(x,z)=>`${x},${z}`,start={x:sx,z:sz,g:0,f:0,parent:null},open=[start],best=new Map([[key(sx,sz),0]]),closed=new Set();
    const directions=[[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]];
    let nearest=start,nearestDistance=Infinity;
    const margin=18,minX=Math.min(sx,gx)-margin,maxX=Math.max(sx,gx)+margin,minZ=Math.min(sz,gz)-margin,maxZ=Math.max(sz,gz)+margin;
    for(let visited=0;open.length&&visited<2500;visited++){
      let index=0;for(let i=1;i<open.length;i++)if(open[i].f<open[index].f)index=i;
      const current=open.splice(index,1)[0],currentKey=key(current.x,current.z);if(closed.has(currentKey))continue;closed.add(currentKey);
      const h=Math.hypot(gx-current.x,gz-current.z);if(h<nearestDistance){nearestDistance=h;nearest=current;}
      if(h<1.1)break;
      for(const [dx,dz] of directions){
        const x=current.x+dx,z=current.z+dz,k=key(x,z),g=current.g+(dx&&dz?1.414:1);
        if(x<minX||x>maxX||z<minZ||z>maxZ||closed.has(k)||(best.get(k)??Infinity)<=g||this.blocked(x*cell,z*cell,radius,from.y))continue;
        if(dx&&dz&&(this.blocked((current.x+dx)*cell,current.z*cell,radius,from.y)||this.blocked(current.x*cell,(current.z+dz)*cell,radius,from.y)))continue;
        best.set(k,g);open.push({x,z,g,f:g+Math.hypot(gx-x,gz-z),parent:current});
      }
    }
    const result=[];for(let node=nearest;node.parent;node=node.parent)result.unshift(new THREE.Vector3(node.x*cell,from.y,node.z*cell));
    if(result.length&&this.clearLine(result.at(-1),to,radius))result.push(to.clone());
    return result;
  }
  move(entity,target,speed,dt,radius=.45){
    const position=entity.g.position;entity.navTimer=(entity.navTimer||0)-dt;
    if(entity.navTimer<=0||!entity.path){entity.path=this.path(position,target,radius);entity.navTimer=.75+(Math.abs(entity.seed||0)%5)*.12;}
    let next=entity.path[0];while(next&&Math.hypot(next.x-position.x,next.z-position.z)<.65){entity.path.shift();next=entity.path[0];}
    if(!next&&this.clearLine(position,target,radius))next=target;
    const before=position.clone();
    if(next){const direction=new THREE.Vector3(next.x-position.x,0,next.z-position.z),distance=direction.length();if(distance>.03){direction.multiplyScalar(Math.min(distance,speed*dt)/distance);const steps=Math.max(1,Math.ceil(direction.length()/.3));for(let i=0;i<steps;i++){const x=position.x+direction.x/steps,z=position.z+direction.z/steps;if(!this.blocked(x,position.z,radius,position.y))position.x=x;if(!this.blocked(position.x,z,radius,position.y))position.z=z;}}}
    const velocity=position.clone().sub(before).multiplyScalar(1/Math.max(.001,dt));
    entity.velocity??=new THREE.Vector3();entity.velocity.lerp(velocity,1-Math.exp(-dt*15));
    if(entity.velocity.lengthSq()>.08){const angle=Math.atan2(entity.velocity.x,entity.velocity.z),delta=THREE.MathUtils.euclideanModulo(angle-entity.g.rotation.y+Math.PI,Math.PI*2)-Math.PI;entity.g.rotation.y+=delta*Math.min(1,dt*12);}
    return velocity.length();
  }
}
