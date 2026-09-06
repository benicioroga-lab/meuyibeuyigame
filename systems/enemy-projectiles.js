import * as THREE from 'three';

const up=new THREE.Vector3(0,1,0),scratchPoint=new THREE.Vector3();
// A continuous segment against the player's actual vertical volume prevents both
// tunnelling on slow frames and damage to a player standing on another floor.
export function segmentPlayerHit(from,to,feet,{radius=.44,height=1.5}={}){
  const direction=to.clone().sub(from),length=direction.length();if(length<.000001)return null;direction.divideScalar(length);
  const bottom=feet.y+radius,top=feet.y+Math.max(radius,height-radius),dx=from.x-feet.x,dz=from.z-feet.z;
  let distance=Infinity;const accept=t=>{if(t>=0&&t<=length&&t<distance)distance=t;};
  if(dx*dx+dz*dz<=radius*radius&&from.y>=bottom&&from.y<=top)accept(0);
  const a=direction.x*direction.x+direction.z*direction.z,b=2*(dx*direction.x+dz*direction.z),c=dx*dx+dz*dz-radius*radius,discriminant=b*b-4*a*c;
  if(a>.000001&&discriminant>=0)for(const t of [(-b-Math.sqrt(discriminant))/(2*a),(-b+Math.sqrt(discriminant))/(2*a)]){const y=from.y+direction.y*t;if(y>=bottom&&y<=top)accept(t);}
  const ray=new THREE.Ray(from,direction);
  for(const y of [bottom,top]){const sphere=new THREE.Sphere(new THREE.Vector3(feet.x,y,feet.z),radius);if(sphere.containsPoint(from))accept(0);else if(ray.intersectSphere(sphere,scratchPoint))accept(from.distanceTo(scratchPoint));}
  return Number.isFinite(distance)?{distance,point:from.clone().addScaledVector(direction,distance)}:null;
}

export class EnemyProjectiles {
  constructor({scene,player,combat,hurtPlayer,active=()=>true,maxShots=64}){
    Object.assign(this,{scene,player,combat,hurtPlayer,active});this.maxShots=Math.min(64,Math.max(1,maxShots));this.shots=[];this.disposed=false;
    this.geometry={core:new THREE.OctahedronGeometry(.095,0),tail:new THREE.CylinderGeometry(.018,.055,.52,5),warning:new THREE.TorusGeometry(.15,.015,4,12)};this.materials=new Map();
  }
  material(color){if(!this.materials.has(color))this.materials.set(color,new THREE.MeshBasicMaterial({color,transparent:true,opacity:.9,depthWrite:false}));return this.materials.get(color);}
  fire(enemy,target=this.player.pos){
    if(this.disposed||!this.active()||enemy.disabled||this.shots.length>=this.maxShots)return false;
    const origin=enemy.g.position.clone().addScaledVector(up,1.28*(enemy.config.scale||1)),feet=target?.clone?target.clone():target?.pos?.clone?.()||target?.g?.position?.clone?.()||this.player.pos.clone(),aim=feet.addScaledVector(up,.72),direction=aim.sub(origin);
    if(direction.lengthSq()<.0001)return false;direction.normalize();
    const modifier=enemy.eliteModifiers?.find(m=>['fire','shock','frost'].includes(m.id)),color=modifier?.color||'#f4b18b',effect=modifier?.id||'kinetic',g=new THREE.Group();g.position.copy(origin);
    const core=new THREE.Mesh(this.geometry.core,this.material(color)),tail=new THREE.Mesh(this.geometry.tail,this.material(color)),warning=new THREE.Mesh(this.geometry.warning,this.material(color));tail.rotation.x=Math.PI/2;tail.position.z=-.25;warning.position.z=.035;g.add(core,tail,warning);g.quaternion.setFromUnitVectors(new THREE.Vector3(0,0,1),direction);tail.visible=false;this.scene.add(g);
    this.shots.push({g,core,tail,warning,source:enemy,direction,speed:enemy.config.projectileSpeed||12,damage:enemy.config.damage*(enemy.damageBuffTime>0?1.16:1),effect,color,age:0,delay:.16,distance:0,maxDistance:(enemy.config.attackRange||14)+7});
    return true;
  }
  impact(shot,hit,player=false){
    const point=hit.point.clone();
    // Feedback is emitted before the source mesh leaves the scene.
    if(player){
      this.combat?.effects?.burst?.(point,shot.color,4,.6);this.hurtPlayer?.(shot.damage,shot.direction.clone().setY(0).normalize());
      if(shot.effect==='frost'){this.player.slowTime=Math.max(this.player.slowTime||0,1.1);this.player.slowFactor=Math.min(this.player.slowFactor||1,.72);}
      if(shot.source.eliteModifiers?.some(m=>m.id==='vampiric')&&!shot.source.disabled)shot.source.health=Math.min(shot.source.maxHealth,shot.source.health+shot.damage*.3);
    }else this.combat?.effects?.impact?.({...hit,kind:hit.kind||'wall',normal:hit.normal||shot.direction.clone().negate()},shot.color);
    this.combat?.effects?.sound?.('impact');
  }
  remove(index){this.shots[index].g.removeFromParent();this.shots.splice(index,1);}
  update(dt){
    if(this.disposed||!this.active()||!Number.isFinite(dt)||dt<=0)return;
    for(let index=this.shots.length-1;index>=0;index--){
      const shot=this.shots[index];shot.age+=dt;
      if(shot.age>4.5||shot.distance>=shot.maxDistance){this.remove(index);continue;}
      let travelTime=dt;
      if(shot.delay>0){
        // The muzzle ring contracts before launch; the target was fixed at AI windup.
        if(shot.source.disabled){this.remove(index);continue;}
        const previous=shot.delay;shot.delay=Math.max(0,shot.delay-dt);shot.warning.scale.setScalar(.75+shot.delay/.16);shot.core.scale.setScalar(1+.5*Math.sin(shot.age*45));
        if(shot.delay>0)continue;travelTime=Math.max(0,dt-previous);shot.warning.visible=false;shot.tail.visible=true;this.combat?.effects?.sound?.(`enemy-${shot.source.type||'ranged'}`);
      }
      const distance=Math.min(shot.speed*travelTime,shot.maxDistance-shot.distance);if(distance<=0)continue;
      const from=shot.g.position.clone(),to=from.clone().addScaledVector(shot.direction,distance),wall=this.combat?.hitWorld?.surfaces(from,shot.direction,distance,{padding:.035}),player=this.player.health>0?segmentPlayerHit(from,to,this.player.pos):null;
      if(wall&&(!player||wall.distance<=player.distance)){this.impact(shot,wall);this.remove(index);continue;}
      if(player){this.impact(shot,player,true);this.remove(index);continue;}
      shot.g.position.copy(to);shot.distance+=distance;shot.core.rotation.z+=dt*7;
    }
  }
  clear(){for(const shot of this.shots)shot.g.removeFromParent();this.shots.length=0;}
  dispose(){if(this.disposed)return;this.clear();this.disposed=true;for(const geometry of Object.values(this.geometry))geometry.dispose();for(const material of this.materials.values())material.dispose();this.materials.clear();}
}
