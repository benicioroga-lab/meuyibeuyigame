// All motifs and timbres are synthesized for this game. No sampled or copied score.
const clamp=(value,min=0,max=1)=>Math.max(min,Math.min(max,Number.isFinite(value)?value:min));
const hz=note=>440*2**((note-69)/12);
const SCORE={
  street:[[50,53,57,60],[46,50,53,57],[48,52,55,60],[45,48,52,57]],
  boss:[[38,45,50,53],[41,48,53,56],[39,46,51,54],[37,44,49,52]],
  melody:[0,null,2,1,null,3,2,null,1,0,null,2,3,null,1,0],
};
const ALIASES={round:'round-complete',critical:'headshot',unlock:'loot',forged:'forge',
  'legendary-drop':'legendary','mythic-drop':'mythic','boss-killed':'boss-kill',
  'power-up':'powerup','triple-kill':'multikill',rampage:'multikill','warning':'spawn-warning',
  'spawn warning':'spawn-warning','reload-magazine':'reload-insert'};

export class GameAudio {
  constructor(context){
    this.context=context;this.active=false;this.disposed=false;this.step=0;this.nextBeat=0;this.intensity=0;this.footClock=0;this.footSide=1;
    this.nodes=new Set();this.voices=new Map();this.voiceLimit=128;this.musicVoiceLimit=82;this.lastCue=new Map();
    this.masterVolume=.5;this.musicVolume=.35;this.effectsVolume=.8;
    this.bossPhase=0;this.event=null;this.healthRatio=1;this.pressure=0;this.duckUntil=0;this.duckLevel=1;
    const c=context;
    this.master=c.createGain();this.limiter=c.createDynamicsCompressor();
    this.limiter.threshold.value=-13;this.limiter.knee.value=12;this.limiter.ratio.value=5;this.limiter.attack.value=.004;this.limiter.release.value=.16;
    this.master.connect(this.limiter).connect(c.destination);
    this.music=c.createGain();this.fx=c.createGain();this.scoreFilter=c.createBiquadFilter();this.musicDuck=c.createGain();
    this.scoreFilter.type='lowpass';this.scoreFilter.frequency.value=7000;
    this.music.connect(this.scoreFilter).connect(this.musicDuck).connect(this.master);this.fx.connect(this.master);
    this.room=c.createConvolver();const impulse=c.createBuffer(2,Math.floor(c.sampleRate*.62),c.sampleRate);
    for(let ch=0;ch<2;ch++){const data=impulse.getChannelData(ch);for(let i=0;i<data.length;i++)data[i]=(Math.random()*2-1)*(1-i/data.length)**3*.28;}
    this.room.buffer=impulse;this.roomReturn=c.createGain();this.roomReturn.gain.value=.10;
    this.room.connect(this.roomReturn).connect(this.master);this.fx.connect(this.room);this.musicDuck.connect(this.room);
    this.noise=c.createBuffer(1,c.sampleRate*2,c.sampleRate);const data=this.noise.getChannelData(0);
    for(let i=0;i<data.length;i++)data[i]=Math.random()*2-1;
    this.setVolume(.5);this.setMix(.35,.8);this.timer=setInterval(()=>this.schedule(),25);
  }
  setVolume(value){if(this.disposed)return;this.masterVolume=clamp(value);this.master.gain.setTargetAtTime(this.masterVolume,this.context.currentTime,.025);}
  setMix(music,effects){
    if(this.disposed)return;this.musicVolume=clamp(music);this.effectsVolume=clamp(effects);
    this.music.gain.setTargetAtTime(this.active?this.musicVolume:0,this.context.currentTime,.07);
    this.fx.gain.setTargetAtTime(this.effectsVolume,this.context.currentTime,.025);
  }
  setActive(active){
    if(this.disposed)return;const wasActive=this.active;this.active=!!active;
    this.music.gain.setTargetAtTime(this.active?this.musicVolume:0,this.context.currentTime,.08);
    if(this.active&&!wasActive){this.nextBeat=this.context.currentTime+.04;this.footClock=.12;}
  }
  voice({at=this.context.currentTime,frequency=200,endFrequency=frequency,duration=.1,level=.1,wave='sine',noise=false,filter='lowpass',cutoff=3500,pan=0,bus=this.fx,attack=.002}={}){
    if(this.disposed||this.context.state!=='running')return null;
    const isMusic=bus===this.music;
    // Music has its own ceiling, reserving enough voices for rapid guns and critical cues.
    if(isMusic&&[...this.voices.values()].filter(v=>v.music).length>=this.musicVoiceLimit)return null;
    if(this.nodes.size>=this.voiceLimit){
      if(isMusic)return null;
      const oldestMusic=[...this.voices.values()].find(v=>v.music);
      if(oldestMusic){try{oldestMusic.source.stop();}catch{}oldestMusic.clean();}else return null;
    }
    const c=this.context;at=Math.max(c.currentTime,Number.isFinite(at)?at:c.currentTime);duration=clamp(duration,.015,4);level=clamp(level,0,.65);
    const source=noise?c.createBufferSource():c.createOscillator(),gain=c.createGain(),eq=c.createBiquadFilter(),stereo=c.createStereoPanner();
    if(noise){source.buffer=this.noise;source.loop=true;}
    else{source.type=wave;source.frequency.setValueAtTime(clamp(frequency,20,18000),at);source.frequency.exponentialRampToValueAtTime(clamp(endFrequency,20,18000),at+duration);}
    eq.type=filter;eq.frequency.value=clamp(cutoff,30,Math.min(18000,c.sampleRate*.45));eq.Q.value=.7;stereo.pan.value=clamp(pan,-1,1);
    gain.gain.setValueAtTime(.0001,at);gain.gain.linearRampToValueAtTime(Math.max(.0001,level),at+Math.min(clamp(attack,.001,.8),duration*.2));gain.gain.exponentialRampToValueAtTime(.0001,at+duration);
    source.connect(eq).connect(gain).connect(stereo).connect(bus);
    let cleaned=false;
    const clean=()=>{if(cleaned)return;cleaned=true;source.onended=null;for(const node of [source,eq,gain,stereo])node.disconnect();this.nodes.delete(source);this.voices.delete(source);};
    source.onended=clean;this.nodes.add(source);this.voices.set(source,{source,music:isMusic,clean});
    source.start(at);source.stop(at+duration+.02);return source;
  }
  duck(duration=.5,level=.6){
    if(this.disposed)return;this.duckUntil=Math.max(this.duckUntil,this.context.currentTime+duration);this.duckLevel=Math.min(this.duckLevel,clamp(level));
    this.musicDuck.gain.setTargetAtTime(this.duckLevel,this.context.currentTime,.025);
  }
  play(type,weapon=null,pan=0){
    if(this.disposed||this.context.state!=='running')return;
    type=String(type).toLowerCase().replaceAll('_','-');type=ALIASES[type]||type;
    const now=this.context.currentTime,v=options=>this.voice({at:now,pan,...options});
    // Reward/impact bursts may represent many kills at the same instant. Consolidate only
    // those identical cues; gunshots and reload steps always retain their precise timing.
    const cooldown={hit:.025,headshot:.065,kill:.05,collect:.06,loot:.13,legendary:.5,mythic:.5,powerup:.18,multikill:.45,elite:.4,'spawn-warning':.6};
    if(cooldown[type]&&now-(this.lastCue.get(type)??-Infinity)<cooldown[type])return;
    if(cooldown[type])this.lastCue.set(type,now);
    const notes=(sequence,{spacing=.075,duration=.3,level=.07,wave='sine'}={})=>sequence.forEach((note,i)=>{
      v({at:now+i*spacing,frequency:hz(note),duration,level,wave,cutoff:2400,pan:pan+(i%2?-.12:.12)});
      v({at:now+i*spacing,frequency:hz(note+12),duration:.08,level:level*.22});
    });
    if(type==='shot'){
      const w=weapon||{},family=String(w.family||w.archetype||w.category||'').toLowerCase();
      const shotgun=/shotgun|escopeta/.test(family),sniper=/sniper|precis[aã]o|rifle de/.test(family),automatic=/smg|autom|submetra/.test(family);
      const heavy=shotgun||sniper||/pesada|launcher|lança/.test(family)||w.effect==='frost';
      const electric=['chain','shock'].includes(w.element||w.effect),suppressed=!!(w.silenced||w.suppressed),volume=suppressed?.48:1;
      // Crisp transient, low body, action noise and a short air tail are mixed separately.
      v({noise:true,filter:'highpass',cutoff:electric?1700:suppressed?500:850,duration:shotgun?.19:sniper?.11:automatic?.045:.075,level:(shotgun?.29:automatic?.12:.22)*volume});
      v({frequency:heavy?125:automatic?260:210,endFrequency:heavy?36:automatic?90:65,duration:sniper?.29:shotgun?.25:automatic?.075:.13,level:(heavy?.36:automatic?.16:.21)*volume,wave:sniper?'sine':'triangle',cutoff:1200});
      v({at:now+.011,noise:true,filter:'bandpass',cutoff:(w.sound||220)*3,duration:heavy?.065:.035,level:.08*volume});
      if(shotgun)v({at:now+.025,noise:true,cutoff:650,duration:.23,level:.15*volume});
      if(sniper){v({at:now+.035,noise:true,filter:'bandpass',cutoff:1900,duration:.2,level:.065*volume,pan:pan-.25});v({at:now+.045,frequency:80,endFrequency:32,duration:.28,level:.1*volume});}
      if(electric){v({frequency:840,endFrequency:150,duration:.15,level:.12,wave:'sawtooth',cutoff:2200});v({frequency:1260,endFrequency:460,duration:.19,level:.05,pan:pan-.15});}
      if(['burn','fire'].includes(w.element||w.effect))v({noise:true,cutoff:1100,duration:.18,level:.09});
      if(['frost','cryo'].includes(w.element||w.effect))for(let i=0;i<3;i++)v({at:now+i*.015,frequency:1700+i*450,endFrequency:900,duration:.15,level:.035,pan:pan+(i-1)*.3});
      if(['corrosive','acid'].includes(w.element||w.effect))v({noise:true,filter:'bandpass',cutoff:2800,duration:.18,level:.085});
      if(['explosive','explosion'].includes(w.element||w.effect))v({frequency:80,endFrequency:28,duration:.3,level:.2});
      return;
    }
    if(['reload-start','reload-insert','reload-chamber','reload-end','empty','shell','equip','holster','inspect'].includes(type)){
      const start=type==='reload-start',empty=type==='empty',shell=type==='shell';
      const weight=weapon&&(/pesada|shotgun|sniper|escopeta/i.test(weapon.family||weapon.category||''))?.78:1;
      v({noise:true,filter:'bandpass',cutoff:(start?1700:shell?4200:empty?2200:2800)*weight,duration:empty?.025:shell?.045:.065,level:empty?.045:shell?.025:.09});
      v({frequency:(start?180:shell?1800:empty?430:390)*weight,endFrequency:shell?900:95,duration:shell?.055:.04,level:shell?.015:.055,wave:'triangle'});
      if(start)v({at:now+.12,noise:true,filter:'highpass',cutoff:2500,duration:.04,level:.045,pan:pan+.15});
      if(type==='reload-chamber'||type==='reload-end')v({at:now+.055,noise:true,filter:'bandpass',cutoff:1400,duration:.04,level:.08});
      if(type==='reload-insert')v({frequency:140,endFrequency:70,duration:.08,level:.065});
      return;
    }
    if(type==='hit'||type==='headshot'||type==='kill'){
      v({noise:true,filter:'bandpass',cutoff:type==='headshot'?1900:1000,duration:.035,level:.07});
      const f=type==='headshot'?1480:type==='kill'?740:980;v({frequency:f,endFrequency:f*.84,duration:type==='kill'?.13:.05,level:type==='kill'?.07:.045});
      if(type==='kill')v({at:now+.04,frequency:1110,endFrequency:900,duration:.15,level:.04});
      if(type==='headshot'){v({frequency:2220,endFrequency:1850,duration:.085,level:.022,pan:pan-.1});v({frequency:105,endFrequency:65,duration:.06,level:.08});}return;
    }
    if(type==='collect'){notes([81,88],{spacing:.025,duration:.1,level:.045});return;}
    if(type==='purchase'){notes([69,73,76],{spacing:.05,duration:.22});return;}
    if(type==='loot'){notes([74,77,81],{spacing:.055,duration:.2,level:.06});return;}
    if(type==='legendary'||type==='mythic'){
      this.duck(1.1,.45);v({frequency:90,endFrequency:42,duration:.32,level:.22});v({noise:true,filter:'highpass',cutoff:2500,duration:.3,level:.085});
      notes(type==='mythic'?[62,69,74,78,81,86]:[62,65,69,74,81],{spacing:.09,duration:.62,level:.105,wave:'triangle'});return;
    }
    if(type==='powerup'){this.duck(.6,.7);notes([62,69,74,81],{spacing:.045,duration:.3,level:.085});v({frequency:180,endFrequency:900,duration:.22,level:.08,wave:'triangle'});return;}
    if(type==='forge'){this.duck(.55,.7);v({noise:true,filter:'bandpass',cutoff:2400,duration:.15,level:.17});v({frequency:120,endFrequency:55,duration:.25,level:.18});notes([62,69,74,78],{spacing:.065,duration:.36,level:.08});return;}
    if(type==='round-complete'||type==='boss-kill'){
      this.duck(type==='boss-kill'?1.7:1,.4);notes(type==='boss-kill'?[50,57,62,65,69,74]:[62,65,69,74],{spacing:.12,duration:.7,level:.105,wave:'triangle'});
      v({frequency:120,endFrequency:38,duration:.3,level:.25});v({noise:true,filter:'highpass',cutoff:2800,duration:.32,level:.07});return;
    }
    if(type==='round-start'){notes([50,57,62],{spacing:.12,duration:.22,level:.08,wave:'triangle'});v({frequency:130,endFrequency:40,duration:.23,level:.2});return;}
    if(type==='boss-start'||type==='boss-phase'){
      this.duck(.8,.5);[0,.17,.34].forEach((delay,i)=>v({at:now+delay,frequency:100+i*15,endFrequency:32,duration:.3,level:.22}));
      notes(type==='boss-start'?[38,45,50,53]:[41,48,53,56],{spacing:.09,duration:.5,level:.08,wave:'sawtooth'});return;
    }
    if(type==='multikill'){notes([74,81,86],{spacing:.045,duration:.16,level:.065});v({frequency:120,endFrequency:48,duration:.1,level:.1});return;}
    if(type==='elite'||type==='spawn-warning'){notes(type==='elite'?[62,61,57]:[74,73],{spacing:.1,duration:.2,level:.065,wave:'triangle'});return;}
    if(type==='step'){v({noise:true,cutoff:800,duration:.055,level:.026});v({frequency:85,endFrequency:48,duration:.045,level:.022});return;}
    if(type==='dog'||type==='bark'){v({frequency:type==='bark'?180:250,endFrequency:90,duration:.11,level:.12,wave:'sawtooth',filter:'bandpass',cutoff:550});v({at:now+.095,frequency:165,endFrequency:80,duration:.13,level:.1,wave:'sawtooth',cutoff:900});return;}
    if(type==='crash'||type==='impact'||type==='explosion'){v({noise:true,cutoff:2400,duration:type==='explosion'?.28:.12,level:.12});v({frequency:145,endFrequency:35,duration:type==='explosion'?.35:.15,level:type==='explosion'?.25:.09,wave:'triangle'});return;}
    if(type==='hurt'){this.duck(.2,.8);v({noise:true,cutoff:650,duration:.13,level:.17});v({frequency:90,endFrequency:36,duration:.18,level:.13});return;}
    if(type.startsWith('enemy-')){
      const kind=type.slice(6),large=/brute|tank|boss/.test(kind),fast=/runner|assassin/.test(kind);
      v({frequency:large?90:fast?310:160,endFrequency:large?45:100,duration:large?.25:.12,level:.07,wave:'sawtooth',filter:'bandpass',cutoff:large?450:900});return;
    }
    v({noise:true,filter:'bandpass',cutoff:type==='dash'?1400:700,duration:.12,level:.045});
  }
  schedule(){
    const c=this.context;if(this.disposed||!this.active||c.state!=='running')return;
    if(this.nextBeat<c.currentTime-.2)this.nextBeat=c.currentTime+.03;
    // Do not replay missed bars after a suspended tab; schedule only a short look-ahead.
    const bpm=this.bossPhase?112+this.bossPhase*4:104+this.intensity*9,stepDuration=60/bpm/4;
    let scheduled=0;while(this.nextBeat<c.currentTime+.12&&scheduled++<8){this.musicStep(this.step++,this.nextBeat);this.nextBeat+=stepDuration;}
  }
  musicStep(index,at){
    const step=index%16,bar=Math.floor(index/16),boss=this.bossPhase>0,blackout=this.event==='blackout';
    const chord=(boss?SCORE.boss:SCORE.street)[Math.floor(bar/2)%4],intensity=this.intensity,quiet=intensity<.22&&!boss;
    const v=options=>this.voice({at,bus:this.music,...options});
    // The same four-note identity survives the change from exploration to a boss fight.
    if(step===0)chord.forEach((note,i)=>{
      v({frequency:hz(note+(boss?12:0)),duration:2.05,level:quiet?.035:.027,attack:.15,wave:'triangle',cutoff:blackout?520:1000,pan:(i-1.5)*.26});
      v({frequency:hz(note+(boss?12:0))*1.003,duration:2.05,level:.009,attack:.18,cutoff:1300,pan:(1.5-i)*.26});
    });
    if((quiet?[0,8]:[0,6,8,11,14]).includes(step)){
      const note=chord[0]-(boss?0:12)+(step===14?12:0);v({frequency:hz(note),duration:step===0?.34:.2,level:quiet?.13:.19});
      v({frequency:hz(note)*2,duration:.11,level:.03,wave:'triangle',cutoff:700});
    }
    if(step===0||step===8||intensity>.55&&(step===6||step===14)){
      v({frequency:142,endFrequency:43,duration:.21,level:quiet?.14:.26});v({noise:true,duration:.023,cutoff:1800,level:.035});
    }
    if((step===4||step===12)&&!blackout){
      v({noise:true,filter:'bandpass',cutoff:1900,duration:.095,level:.07+intensity*.07,pan:.04});
      v({frequency:190,endFrequency:110,duration:.07,level:.05});v({at:at+.014,noise:true,filter:'highpass',cutoff:4000,duration:.035,level:.035,pan:-.15});
    }
    if(!blackout&&(step%2===0&&!quiet||intensity>.65))v({noise:true,filter:'highpass',cutoff:6500,duration:step%4===2?.05:.024,level:step%2===0?.032:.016,pan:step%4===0?-.28:.28});
    if(!quiet&&!blackout&&[3,7,10,15].includes(step))v({frequency:step===7?560:390,endFrequency:220,duration:.065,level:.035,pan:step%2?.35:-.35});
    if(step%4===2&&(bar%4<3||intensity>.35)&&!blackout){
      const motif=SCORE.melody[(Math.floor(step/4)+bar*4)%16];
      if(motif!==null){const note=chord[motif]+(boss?24:12);
        v({frequency:hz(note),duration:.36,level:boss?.065:.055,pan:Math.sin(bar)*.35});v({frequency:hz(note+12),duration:.1,level:.015});
        v({at:at+.23,frequency:hz(note),duration:.24,level:.018,pan:-Math.sin(bar)*.45});
      }
    }
    if(boss&&step%4===0)v({frequency:hz(chord[0]+12),endFrequency:hz(chord[0]),duration:.24,level:.07+this.bossPhase*.018,wave:'triangle',cutoff:900,pan:step===0?-.35:.35});
    if(this.healthRatio<.25&&(step===0||step===2))v({frequency:58,endFrequency:42,duration:.16,level:.12*(1-this.healthRatio),cutoff:180});
  }
  update(dt,{moving=false,onGround=true,enemies=0,round=1,boss=false,event=null,healthRatio=1,pressure=0}={}){
    if(this.disposed)return;dt=clamp(dt,0,.25);
    this.bossPhase=boss?clamp(typeof boss==='object'?boss.phase||1:typeof boss==='number'?boss:1,1,3):0;
    this.event=String(event?.id||event?.type||event||'').toLowerCase().replaceAll('_','-');this.healthRatio=clamp(healthRatio);this.pressure=clamp(pressure);
    const target=clamp(enemies/20+this.pressure*.32+(this.bossPhase?.25:0)+(round>20?.08:0));
    this.intensity+=(target-this.intensity)*Math.min(1,dt*(target>this.intensity?2:1.15));
    this.scoreFilter.frequency.setTargetAtTime(this.event==='blackout'?950:3200+this.intensity*5200,this.context.currentTime,.35);
    if(this.duckUntil<=this.context.currentTime&&this.duckLevel!==1){this.duckLevel=1;this.musicDuck.gain.setTargetAtTime(1,this.context.currentTime,.16);}
    this.footClock-=dt;
    if(this.active&&moving&&onGround&&this.footClock<=0){this.footClock=.31;this.footSide*=-1;this.play('step',null,this.footSide*.12);}
  }
  dispose(){
    if(this.disposed)return;this.disposed=true;this.active=false;clearInterval(this.timer);this.timer=null;
    for(const voice of [...this.voices.values()]){try{voice.source.stop();}catch{}voice.clean();}
    for(const node of [this.music,this.fx,this.scoreFilter,this.musicDuck,this.master,this.limiter,this.room,this.roomReturn])node.disconnect();
    this.room.buffer=null;this.noise=null;this.lastCue.clear();
  }
}
