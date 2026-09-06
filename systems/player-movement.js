import * as THREE from 'three';

// Feet are the origin. Sweep horizontal motion so a dash cannot tunnel through walls.
export function movePlayer(player,dt,{keys,world,navigation,upgrades={},modifiers={},bonuses={}}){
  const forward=Number(!!(keys.KeyW||keys.ArrowUp))-Number(!!(keys.KeyS||keys.ArrowDown))-(keys.touchY||0);
  const right=Number(!!(keys.KeyD||keys.ArrowRight))-Number(!!(keys.KeyA||keys.ArrowLeft))+(keys.touchX||0);
  const direction=new THREE.Vector3(Math.sin(player.cameraYaw)*forward-Math.cos(player.cameraYaw)*right,0,Math.cos(player.cameraYaw)*forward+Math.sin(player.cameraYaw)*right);
  if(direction.lengthSq()>1)direction.normalize();
  const speed=(5.6+(upgrades.speed||0)*.42)*(modifiers.moveSpeed||1)*(bonuses.movementMultiplier||1)*(player.aiming?.7:1)*(player.dash>0?2.2+(upgrades.dash||0)*.12:1)*(player.downed?.22:1);
  player.slowTime=Math.max(0,(player.slowTime||0)-dt);
  player.moveVelocity.lerp(direction.multiplyScalar(speed*(player.slowTime>0?player.slowFactor||.7:1)),1-Math.exp(-dt*22));
  const delta=player.moveVelocity.clone().multiplyScalar(dt),steps=Math.max(1,Math.ceil(delta.length()/.18));
  for(let i=0;i<steps;i++){
    for(const axis of ['x','z']){
      const candidate=player.pos.clone();candidate[axis]+=delta[axis]/steps;
      const ground=world.heightAt(candidate.x,candidate.z,player.pos.y);
      const feet=player.onGround&&ground-player.pos.y<=.56&&ground>=player.pos.y-.6?ground:player.pos.y;
      if(Number.isFinite(ground)&&ground-player.pos.y<=.56&&!navigation.blocked(candidate.x,candidate.z,.38,feet,1.4)){
        player.pos[axis]=candidate[axis];if(player.onGround&&ground>=player.pos.y-.6)player.pos.y=ground;
      }
    }
  }
  const b=world.bounds;player.pos.x=THREE.MathUtils.clamp(player.pos.x,b.minX+.7,b.maxX-.7);player.pos.z=THREE.MathUtils.clamp(player.pos.z,b.minZ+.7,b.maxZ-.7);
  const floor=world.heightAt(player.pos.x,player.pos.z,player.pos.y);
  if(player.pos.y>floor+.1)player.onGround=false;
  if(!player.onGround){
    player.velocity.y-=21*dt;
    // Sweep vertically as well: an upgraded jump must not skip a thin ceiling,
    // and falling from a rooftop must land on the first floor crossed.
    const travel=player.velocity.y*dt,verticalSteps=Math.max(1,Math.ceil(Math.abs(travel)/.15)),stepY=travel/verticalSteps;
    for(let i=0;i<verticalSteps;i++){
      const nextY=player.pos.y+stepY;
      if(stepY>0&&navigation.blocked(player.pos.x,player.pos.z,.35,nextY,1.4)){player.velocity.y=0;break;}
      const landing=world.heightAt(player.pos.x,player.pos.z,player.pos.y);
      if(stepY<=0&&nextY<=landing){player.pos.y=landing;player.onGround=true;player.velocity.y=0;break;}
      player.pos.y=nextY;
    }
  }
  player.groundY=world.heightAt(player.pos.x,player.pos.z,player.pos.y);
  if(player.pos.y< -12){player.pos.copy(world.spawn);player.velocity.set(0,0,0);player.onGround=true;}
  if(player.moveVelocity.lengthSq()>.12||player.aiming){const angle=player.aiming?player.cameraYaw:Math.atan2(player.moveVelocity.x,player.moveVelocity.z);player.dir+=THREE.MathUtils.euclideanModulo(angle-player.dir+Math.PI,Math.PI*2)-Math.PI;}
  for(const key of ['dash','dashCooldown','barkCooldown','firing','damageCooldown','shieldTime'])player[key]=Math.max(0,(player[key]||0)-dt);
  if(!player.shieldTime)player.shield=0;
}
