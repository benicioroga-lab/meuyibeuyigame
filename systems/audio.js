// Original adaptive score and layered sound design. Buses share a limiter and a short room;
// transient nodes disconnect on completion, while scheduling stays independent of rendering.
export class GameAudio {
  constructor(context){
    this.context=context;this.active=false;this.step=0;this.nextBeat=0;this.intensity=0;this.footClock=0;this.nodes=new Set();this.masterVolume=.5;this.musicVolume=.35;this.effectsVolume=.8;
    const c=context;this.master=c.createGain();this.limiter=c.createDynamicsCompressor();this.limiter.threshold.value=-13;this.limiter.knee.value=12;this.limiter.ratio.value=5;this.limiter.attack.value=.004;this.limiter.release.value=.16;this.master.connect(this.limiter).connect(c.destination);
    this.music=c.createGain();this.fx=c.createGain();this.music.connect(this.master);this.fx.connect(this.master);
    this.room=c.createConvolver();const impulse=c.createBuffer(2,Math.floor(c.sampleRate*.72),c.sampleRate);for(let ch=0;ch<2;ch++){const data=impulse.getChannelData(ch);for(let i=0;i<data.length;i++)data[i]=(Math.random()*2-1)*Math.pow(1-i/data.length,3)*.36;}this.room.buffer=impulse;
    this.roomReturn=c.createGain();this.roomReturn.gain.value=.11;this.room.connect(this.roomReturn).connect(this.master);this.fx.connect(this.room);this.music.connect(this.room);
    this.noise=c.createBuffer(1,c.sampleRate*2,c.sampleRate);const data=this.noise.getChannelData(0);for(let i=0;i<data.length;i++)data[i]=Math.random()*2-1;
    this.setVolume(.5);this.setMix(.35,.8);this.timer=setInterval(()=>this.schedule(),25);
  }
  setVolume(value){this.masterVolume=value;this.master.gain.setTargetAtTime(value,this.context.currentTime,.025);}
  setMix(music,effects){this.musicVolume=music;this.effectsVolume=effects;this.music.gain.setTargetAtTime(this.active?music:0,this.context.currentTime,.07);this.fx.gain.setTargetAtTime(effects,this.context.currentTime,.025);}
  setActive(active){this.active=active;this.music.gain.setTargetAtTime(active?this.musicVolume:0,this.context.currentTime,.08);if(active)this.nextBeat=Math.max(this.nextBeat,this.context.currentTime+.04);}
  voice({at=this.context.currentTime,frequency=200,endFrequency=frequency,duration=.1,level=.1,wave='sine',noise=false,filter='lowpass',cutoff=3500,pan=0,bus=this.fx,attack=.002}){
    if(this.nodes.size>=120)return;
    const c=this.context,source=noise?c.createBufferSource():c.createOscillator(),gain=c.createGain(),eq=c.createBiquadFilter(),stereo=c.createStereoPanner();
    if(noise){source.buffer=this.noise;source.loop=true;}else{source.type=wave;source.frequency.setValueAtTime(Math.max(20,frequency),at);source.frequency.exponentialRampToValueAtTime(Math.max(20,endFrequency),at+duration);}
    eq.type=filter;eq.frequency.value=cutoff;eq.Q.value=.7;stereo.pan.value=Math.max(-1,Math.min(1,pan));
    gain.gain.setValueAtTime(.0001,at);gain.gain.linearRampToValueAtTime(Math.max(.0001,level),at+Math.min(attack,duration*.2));gain.gain.exponentialRampToValueAtTime(.0001,at+duration);
    source.connect(eq).connect(gain).connect(stereo).connect(bus);source.start(at);source.stop(at+duration+.02);this.nodes.add(source);
    source.onended=()=>{source.disconnect();eq.disconnect();gain.disconnect();stereo.disconnect();this.nodes.delete(source);};
  }
  play(type,weapon=null,pan=0){
    if(this.context.state!=='running')return;const now=this.context.currentTime,v=options=>this.voice({at:now,pan,...options});
    if(type==='shot'){
      const heavy=weapon.category==='PESADA'||weapon.effect==='frost',automatic=weapon.category==='AUTOMÁTICA',electric=weapon.effect==='chain';
      // Attack, body and mechanical tail have separate envelopes. No long ring masks the next shot.
      v({noise:true,filter:'highpass',cutoff:electric?1700:850,duration:heavy?.17:.07,level:automatic?.13:.23});
      v({frequency:heavy?130:220,endFrequency:heavy?38:65,duration:heavy?.23:.12,level:heavy?.35:.2,wave:'triangle',cutoff:1200});
      v({at:now+.012,noise:true,filter:'bandpass',cutoff:weapon.sound*3,duration:.045,level:.09});
      v({at:now+.055,frequency:1200,endFrequency:480,duration:.027,level:.035,wave:'square',cutoff:2200,pan:pan+.12});
      if(electric){v({frequency:840,endFrequency:150,duration:.16,level:.13,wave:'sawtooth',cutoff:2400});v({frequency:1260,endFrequency:460,duration:.22,level:.06,pan:-.15});}
      if(weapon.effect==='burn')v({noise:true,cutoff:1100,duration:.21,level:.12});
      if(weapon.effect==='frost')for(let i=0;i<3;i++)v({at:now+i*.015,frequency:1700+i*450,endFrequency:900,duration:.18,level:.04,pan:(i-1)*.3});
      return;
    }
    if(type==='reload-start'||type==='reload-end'||type==='empty'){
      const start=type==='reload-start',empty=type==='empty';v({noise:true,filter:'bandpass',cutoff:start?1700:2800,duration:empty?.035:.07,level:empty?.055:.12});v({frequency:start?180:390,endFrequency:90,duration:.045,level:.07,wave:'triangle'});
      if(start)v({at:now+.13,noise:true,filter:'highpass',cutoff:2500,duration:.045,level:.075,pan:.18});return;
    }
    if(type==='hit'||type==='critical'||type==='kill'){
      v({noise:true,filter:'bandpass',cutoff:1000,duration:.045,level:.085});
      const f=type==='critical'?1320:type==='kill'?740:980;v({frequency:f,endFrequency:f*.8,duration:type==='kill'?.16:.055,level:type==='kill'?.09:.04});
      if(type==='kill')v({at:now+.04,frequency:1110,endFrequency:900,duration:.18,level:.05});return;
    }
    if(type==='purchase'||type==='round'||type==='collect'||type==='unlock'){
      const notes=type==='collect'?[880,1320]:type==='purchase'?[440,554.37,659.25]:[293.66,349.23,440,587.33];
      notes.forEach((f,i)=>{v({at:now+i*.065,frequency:f,duration:type==='collect'?.1:.3,level:.075,wave:'sine',pan:(i-1)*.1});v({at:now+i*.065,frequency:f*2,duration:.08,level:.02});});return;
    }
    if(type==='step'){v({noise:true,filter:'lowpass',cutoff:800,duration:.065,level:.035});v({frequency:85,endFrequency:48,duration:.05,level:.025});return;}
    if(type==='dog'||type==='bark'){v({frequency:type==='bark'?180:250,endFrequency:90,duration:.11,level:.14,wave:'sawtooth',filter:'bandpass',cutoff:550});v({at:now+.095,frequency:165,endFrequency:80,duration:.13,level:.11,wave:'sawtooth',cutoff:900});return;}
    if(type==='crash'||type==='impact'){v({noise:true,cutoff:2400,duration:.12,level:.12});v({frequency:145,endFrequency:50,duration:.15,level:.09,wave:'triangle'});return;}
    if(type==='hurt'){v({noise:true,cutoff:650,duration:.16,level:.2});v({frequency:90,endFrequency:36,duration:.22,level:.15});return;}
    v({noise:true,filter:'bandpass',cutoff:type==='dash'?1400:700,duration:.14,level:.055});
  }
  schedule(){
    const c=this.context;if(!this.active||c.state!=='running')return;
    if(this.nextBeat<c.currentTime-.2)this.nextBeat=c.currentTime+.03;
    const stepDuration=60/104/4;
    while(this.nextBeat<c.currentTime+.12){this.musicStep(this.step++,this.nextBeat);this.nextBeat+=stepDuration;}
  }
  musicStep(index,at){
    const step=index%16,bar=Math.floor(index/16),chord=[[50,53,57,60],[46,50,53,57],[48,52,55,60],[45,48,52,57]][Math.floor(bar/2)%4];
    const hz=midi=>440*Math.pow(2,(midi-69)/12),intensity=this.intensity,v=options=>this.voice({at,bus:this.music,...options});
    // Warm harmony, syncopated bass and a restrained percussion bed. Hordes add momentum.
    if(step===0)chord.forEach((note,i)=>{v({frequency:hz(note),duration:2.15,level:.04,attack:.12,wave:'triangle',cutoff:900,pan:(i-1.5)*.28});v({frequency:hz(note)*1.003,duration:2.15,level:.013,attack:.16,cutoff:1200,pan:(1.5-i)*.28});});
    if([0,6,8,11,14].includes(step)){const note=chord[0]-12+(step===14?12:0);v({frequency:hz(note),duration:step===0?.35:.22,level:.22,wave:'sine'});v({frequency:hz(note)*2,duration:.12,level:.035,wave:'triangle',cutoff:700});}
    if(step===0||step===8||intensity>.45&&(step===6||step===14)){v({frequency:142,endFrequency:43,duration:.22,level:.32});v({noise:true,duration:.025,cutoff:1800,level:.045});}
    if(step===4||step===12){v({noise:true,filter:'bandpass',cutoff:1900,duration:.115,level:.12+intensity*.07,pan:.04});v({frequency:190,endFrequency:110,duration:.08,level:.08});v({at:at+.014,noise:true,filter:'highpass',cutoff:4000,duration:.045,level:.06,pan:-.15});}
    if(step%2===0||intensity>.5){v({noise:true,filter:'highpass',cutoff:6500,duration:step%4===2?.06:.028,level:step%2===0?.043:.02,pan:step%4===0?-.28:.28});}
    if([3,7,10,15].includes(step))v({frequency:step===7?560:390,endFrequency:220,duration:.075,level:.05,wave:'sine',pan:step%2?.35:-.35});
    if(step%4===2&&(bar%4<3||intensity>.35)){
      const note=chord[(Math.floor(step/4)+bar)%4]+12;v({frequency:hz(note),duration:.4,level:.075,pan:Math.sin(bar)*.35});v({frequency:hz(note)*2,duration:.12,level:.02});
      v({at:at+.23,frequency:hz(note),duration:.27,level:.023,pan:-Math.sin(bar)*.45});
    }
  }
  update(dt,{moving=false,onGround=true,enemies=0,round=1}={}){
    this.intensity+=(Math.min(1,enemies/15+(round%5===0?.15:0))-this.intensity)*Math.min(1,dt*2);
    this.footClock-=dt;if(moving&&onGround&&this.footClock<=0){this.footClock=.31;this.play('step',null,this.step%2?.1:-.1);}
  }
  dispose(){clearInterval(this.timer);for(const source of this.nodes){try{source.stop();}catch{}}for(const node of [this.music,this.fx,this.master,this.limiter,this.room,this.roomReturn])node.disconnect();this.nodes.clear();}
}
