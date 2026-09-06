import {DISTRICTS} from './world-detail.js';

// North stays up. Terrain elevation and objective symbols remain readable in a
// small fixed HUD; only the player arrow and its sight cone rotate.
export function drawTacticalMap(canvas,{player,colliders=[],enemies=[],collectibles=[],companion,ammo=[],round=1,world=null,interactions=null,bossZones=null,quest=null},range=26){
  if(!canvas)return;const ctx=canvas.getContext('2d');if(!ctx)return;
  const size=canvas.width,center=size/2,scale=center/range;
  const point=(x,z)=>({x:center+(x-player.pos.x)*scale,y:center-(z-player.pos.z)*scale});
  const rect=(x,z,w,d,fill,stroke=null)=>{const p=point(x,z);ctx.fillStyle=fill;ctx.fillRect(p.x-w*scale/2,p.y-d*scale/2,w*scale,d*scale);if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=.8;ctx.strokeRect(p.x-w*scale/2,p.y-d*scale/2,w*scale,d*scale);}};
  ctx.clearRect(0,0,size,size);ctx.save();ctx.beginPath();ctx.roundRect(0,0,size,size,14);ctx.clip();ctx.fillStyle=world?'#394d48':'#596b59';ctx.fillRect(0,0,size,size);
  if(world){
    for(const area of world.mapAreas||[]){
      if(Math.abs(area.x-player.pos.x)>range+area.width||Math.abs(area.z-player.pos.z)>range+area.depth)continue;
      const color=area.type==='boss'?'#857061':area.type==='stairs'?'#b0a486':area.type==='ramp'?'#a6b09a':area.height>=11?'#92a68b':area.height>=5?'#839b83':'#6e897c';
      rect(area.x,area.z,area.width,area.depth,color);
      if(area.type==='stairs'){for(let z=area.z-area.depth/2;z<area.z+area.depth/2;z+=1.7)rect(area.x,z,area.width,.11,'#e0d5b1');}
      if(area.type==='ramp'){const p=point(area.x,area.z);ctx.strokeStyle='#dfdfbf';ctx.lineWidth=1.3;ctx.beginPath();ctx.moveTo(p.x,p.y+6);ctx.lineTo(p.x,p.y-6);ctx.moveTo(p.x-3,p.y-3);ctx.lineTo(p.x,p.y-6);ctx.lineTo(p.x+3,p.y-3);ctx.stroke();}
    }
    // The gallery is a separate walkable layer below the middle street.
    if(player.pos.y<3&&player.pos.z>-15&&player.pos.z<26){rect(0,4,6,40,'#4e736b','#99c6b3');rect(3,22,12,4,'#4e736b');}
    for(const c of colliders){
      if(c.surface||c.disabled||c.prop?.userData.broken||Math.abs(c.x-player.pos.x)>range+c.width||Math.abs(c.z-player.pos.z)>range+c.depth)continue;
      if((c.minY??0)>player.pos.y+2.8||c.height<player.pos.y+.25)continue;
      rect(c.x,c.z,c.width,c.depth,c.door?'#d3ad6e':c.prop?'#736a50':'#3f5650',c.door?'#f0cf83':c.prop?null:'#adbaa0');
    }
  }else{
    rect(-82,0,106,500,'#355b65');rect(-18,0,23,400,'#aaa17c');rect(-3,2,38,140,'#8d9987');rect(38,0,23,120,'#465753');
    for(let z=-54;z<60;z+=8)rect(38,z,.35,3,'#b7b994');
    for(const c of colliders){if(!c.disabled)rect(c.x,c.z,c.width,c.depth,c.prop?'#736a50':'#334a46',c.prop?null:'#899983');}
  }
  ctx.strokeStyle='#d8dcc315';ctx.lineWidth=1;for(let x=0;x<size;x+=size/6){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,size);ctx.moveTo(0,x);ctx.lineTo(size,x);ctx.stroke();}
  const dot=(position,color,r=2.5,outline=false)=>{
    const p=point(position.x,position.z);if(p.x<4||p.x>size-4||p.y<4||p.y>size-4)return;
    ctx.beginPath();ctx.arc(p.x,p.y,r,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();if(outline){ctx.strokeStyle='#173a37';ctx.lineWidth=1.5;ctx.stroke();}
    if(Math.abs((position.y||0)-player.pos.y)>2.5){ctx.fillStyle=color;ctx.font='700 9px sans-serif';ctx.textAlign='center';ctx.fillText(position.y>player.pos.y?'⌃':'⌄',p.x,p.y-r-2);}
  };
  for(const item of collectibles)if(!item.userData.claimed)dot(item.position,item.userData.healing?'#b2dfa8':'#e0c88b',1.6);
  for(const box of ammo)dot(box.g.position,'#b3d5d0',2.7,true);
  for(const enemy of enemies)if(!enemy.disabled)dot(enemy.g.position,enemy.elite||enemy.type==='captain'?'#ffd176':'#f1a08c',enemy.elite||enemy.type==='captain'?4:2.7,true);
  if(companion)dot(companion.g.position,'#a2ead6',4,true);
  const symbol=(position,text,color)=>{const p=point(position.x,position.z);if(p.x<9||p.x>size-9||p.y<14||p.y>size-20)return;ctx.fillStyle='#294d46';ctx.fillRect(p.x-6,p.y-6,12,12);ctx.font='700 10px sans-serif';ctx.textAlign='center';ctx.fillStyle=color;ctx.fillText(text,p.x,p.y+3.5);};
  if(world){
    for(const item of interactions||world.interactions||[]){if(item.used||item.opened||item.claimed||item.completed||(item.secret&&Math.hypot(item.position.x-player.pos.x,item.position.z-player.pos.z)>9))continue;
      const text={chest:'▣',vault:'▣',shop:'$',forge:'⚒',challenge:'!',quest:'?',door:'▥'}[item.type]||'·';symbol(item.position,text,(item.unlockRound||1)>round?'#869e8d':item.type==='forge'?'#d9c5ee':'#eed6a1');}
    for(const zone of bossZones||world.bossZones||[])if(!zone.defeated)symbol(zone.center||zone.position,'☠',round>=zone.unlockRound?'#efad91':'#8e9b87');
  }
  if(quest?.target&&!quest.completed){
    const target=quest.target,p=point(target.x,target.z),dx=p.x-center,dy=p.y-center,bound=(center-19)/Math.max(Math.abs(dx),Math.abs(dy),1),factor=Math.min(1,bound),qx=center+dx*factor,qy=Math.max(24,Math.min(size-33,center+dy*factor));
    ctx.strokeStyle='#eadd9c9c';ctx.lineWidth=1;ctx.setLineDash([3,4]);ctx.beginPath();ctx.moveTo(center,center);ctx.lineTo(qx,qy);ctx.stroke();ctx.setLineDash([]);
    ctx.fillStyle='#ead999';ctx.strokeStyle='#334e44';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(qx,qy-7);ctx.lineTo(qx+6,qy);ctx.lineTo(qx,qy+7);ctx.lineTo(qx-6,qy);ctx.closePath();ctx.fill();ctx.stroke();
    const distance=Math.round(Math.hypot(target.x-player.pos.x,target.z-player.pos.z)),height=Math.round(target.y-player.pos.y),altitude=Math.abs(height)>=2?` · ${height>0?'↑':'↓'}${Math.abs(height)}m`:'';
    ctx.fillStyle='#183a32e8';ctx.fillRect(0,size-20,size-76,20);ctx.fillStyle='#f0e1a8';ctx.font='700 9px sans-serif';ctx.textAlign='left';ctx.fillText(`${size>=300?(quest.name||'ENTREGA').toUpperCase():'ALVO'} · ${distance}m${altitude}`,7,size-7,size-91);
    if(size>=300){ctx.textAlign='center';ctx.fillText('ENTREGA',qx,Math.max(14,qy-12));}
  }
  if(size>=300){ctx.font='600 10px sans-serif';ctx.textAlign='center';ctx.fillStyle='#ebe8ce';for(const area of world?.districts||DISTRICTS){if(world&&Math.abs(area.y-player.pos.y)>4)continue;const p=point(area.x,area.z);if(p.x>35&&p.x<size-35&&p.y>20&&p.y<size-20)ctx.fillText(area.name.toUpperCase(),p.x,p.y-15);}}
  ctx.save();ctx.translate(center,center);ctx.rotate(player.cameraYaw);const gradient=ctx.createRadialGradient(0,0,0,0,0,size*.29);gradient.addColorStop(0,'#f8e8b343');gradient.addColorStop(1,'#f8e8b300');ctx.fillStyle=gradient;ctx.beginPath();ctx.moveTo(0,0);ctx.arc(0,0,size*.29,-Math.PI/2-.55,-Math.PI/2+.55);ctx.closePath();ctx.fill();
  ctx.beginPath();ctx.moveTo(0,-8);ctx.lineTo(5.5,6);ctx.lineTo(0,3);ctx.lineTo(-5.5,6);ctx.closePath();ctx.fillStyle='#fff2c5';ctx.strokeStyle='#253d3e';ctx.lineWidth=2;ctx.stroke();ctx.fill();ctx.restore();
  ctx.fillStyle='#153137df';ctx.fillRect(size-76,size-20,76,20);ctx.fillStyle='#e6e7ce';ctx.font='600 9px sans-serif';ctx.textAlign='center';ctx.fillText(world?`${range}m · ↑${Math.round(player.pos.y)}m`:`${range} m`,size-38,size-7);
  ctx.fillStyle='#203a3e';ctx.fillRect(center-9,0,18,17);ctx.fillStyle='#f2ddb0';ctx.fillText('N',center,12);
  ctx.restore();ctx.strokeStyle='#c4c7a963';ctx.lineWidth=2;ctx.beginPath();ctx.roundRect(1,1,size-2,size-2,13);ctx.stroke();
}
