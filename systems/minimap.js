import {DISTRICTS} from './world-detail.js';

// North stays up. Only the player marker and sight cone rotate.
export function drawTacticalMap(canvas,{player,colliders,enemies,collectibles,companion,ammo=[],round},range=32){
  if(!canvas)return;const ctx=canvas.getContext('2d'),size=canvas.width,center=size/2,scale=center/range;
  const point=(x,z)=>({x:center+(x-player.pos.x)*scale,y:center-(z-player.pos.z)*scale});
  const rect=(x,z,w,d,fill,stroke=null)=>{const p=point(x,z);ctx.fillStyle=fill;ctx.fillRect(p.x-w*scale/2,p.y-d*scale/2,w*scale,d*scale);if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=1;ctx.strokeRect(p.x-w*scale/2,p.y-d*scale/2,w*scale,d*scale);}};
  ctx.clearRect(0,0,size,size);ctx.save();ctx.beginPath();ctx.roundRect(0,0,size,size,14);ctx.clip();ctx.fillStyle='#596b59';ctx.fillRect(0,0,size,size);
  rect(-82,0,106,500,'#355b65');rect(-18,0,23,400,'#aaa17c');rect(-3,2,38,140,'#8d9987');rect(38,0,23,120,'#465753');
  for(let z=-54;z<60;z+=8)rect(38,z,.35,3,'#b7b994');
  rect(17,18,13,19,'#ad926e');rect(5,50,21,20,'#729271');rect(37,45,17,23,'#bd906c');rect(36,-34,19,25,'#687970');rect(55,7,20,5.5,'#b4ad90');
  const plaza=point(-2,-30);ctx.fillStyle='#b8b08e';ctx.beginPath();ctx.arc(plaza.x,plaza.y,12*scale,0,Math.PI*2);ctx.fill();
  ctx.strokeStyle='#d8dcc311';ctx.lineWidth=1;for(let x=0;x<size;x+=size/6){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,size);ctx.moveTo(0,x);ctx.lineTo(size,x);ctx.stroke();}
  for(const c of colliders){if(Math.abs(c.x-player.pos.x)>range+c.width||Math.abs(c.z-player.pos.z)>range+c.depth)continue;rect(c.x,c.z,c.width,c.depth,c.prop?'#736a50':'#334a46',c.prop?null:'#899983');}
  const dot=(position,color,r=2.5,outline=false)=>{const p=point(position.x,position.z);if(p.x<4||p.x>size-4||p.y<4||p.y>size-4)return;ctx.beginPath();ctx.arc(p.x,p.y,r,0,Math.PI*2);ctx.fillStyle=color;ctx.fill();if(outline){ctx.strokeStyle='#152b30';ctx.lineWidth=1.5;ctx.stroke();}};
  for(const item of collectibles)if(!item.userData.claimed)dot(item.position,item.userData.healing?'#b2dfa8':'#e0c88b',1.6);
  for(const box of ammo)dot(box.g.position,'#b3d5d0',2.7,true);
  for(const enemy of enemies)if(!enemy.disabled)dot(enemy.g.position,enemy.type==='captain'?'#ffd176':'#f1a08c',enemy.type==='captain'?5:3,true);
  if(companion)dot(companion.g.position,'#a2ead6',4,true);
  if(size>=300){ctx.font='600 10px sans-serif';ctx.textAlign='center';ctx.fillStyle='#ebe8ce';for(const area of DISTRICTS){const p=point(area.x,area.z);if(p.x>35&&p.x<size-35&&p.y>20&&p.y<size-20)ctx.fillText(area.name.toUpperCase(),p.x,p.y-15);}}
  ctx.save();ctx.translate(center,center);ctx.rotate(player.cameraYaw);const gradient=ctx.createRadialGradient(0,0,0,0,0,size*.32);gradient.addColorStop(0,'#f8e8b333');gradient.addColorStop(1,'#f8e8b300');ctx.fillStyle=gradient;ctx.beginPath();ctx.moveTo(0,0);ctx.arc(0,0,size*.32,-Math.PI/2-.55,-Math.PI/2+.55);ctx.closePath();ctx.fill();ctx.beginPath();ctx.moveTo(0,-8);ctx.lineTo(5.5,6);ctx.lineTo(0,3);ctx.lineTo(-5.5,6);ctx.closePath();ctx.fillStyle='#fff2c5';ctx.strokeStyle='#253d3e';ctx.lineWidth=2;ctx.stroke();ctx.fill();ctx.restore();
  ctx.fillStyle='#153137c9';ctx.fillRect(size-54,size-19,54,19);ctx.fillStyle='#e6e7ce';ctx.font='600 10px sans-serif';ctx.textAlign='center';ctx.fillText(`${range} m`,size-27,size-6);ctx.fillStyle='#203a3e';ctx.fillRect(center-9,0,18,17);ctx.fillStyle='#f2ddb0';ctx.fillText('N',center,12);
  ctx.restore();ctx.strokeStyle='#c4c7a963';ctx.lineWidth=2;ctx.beginPath();ctx.roundRect(1,1,size-2,size-2,13);ctx.stroke();
}
