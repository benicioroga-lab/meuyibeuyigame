import test from 'node:test';
import assert from 'node:assert/strict';
import {GameAudio} from '../systems/audio.js';

class Param {
  constructor(){this.value=0;this.events=[];}
  setValueAtTime(value,time){this.value=value;this.events.push({type:'set',value,time});}
  exponentialRampToValueAtTime(value,time){this.events.push({type:'ramp',value,time});}
  linearRampToValueAtTime(value,time){this.events.push({type:'linear',value,time});}
  setTargetAtTime(value,time,constant){this.value=value;this.events.push({type:'target',value,time,constant});}
}
class Node {
  constructor(context,kind){
    this.context=context;this.kind=kind;this.connections=[];this.disconnected=false;
    for(const name of ['frequency','gain','Q','pan','threshold','knee','ratio','attack','release'])this[name]=new Param();
    context.allNodes.push(this);
  }
  connect(node){assert.ok(!this.disconnected);this.connections.push(node);return node;}
  disconnect(){this.disconnected=true;this.connections=[];}
  start(at){this.startAt=at;this.context.sources.push(this);}
  stop(at=this.context.currentTime){this.stopAt=at;}
}
class Context {
  constructor(){this.state='running';this.currentTime=0;this.sampleRate=48000;this.allNodes=[];this.sources=[];this.destination=new Node(this,'destination');}
  createGain(){return new Node(this,'gain');}
  createDynamicsCompressor(){return new Node(this,'compressor');}
  createBiquadFilter(){return new Node(this,'filter');}
  createStereoPanner(){return new Node(this,'pan');}
  createConvolver(){return new Node(this,'convolver');}
  createOscillator(){return new Node(this,'oscillator');}
  createBufferSource(){return new Node(this,'noise');}
  createBuffer(channels,length){const data=Array.from({length:channels},()=>new Float32Array(length));return {getChannelData:i=>data[i]};}
  advance(time){this.currentTime+=time;for(const source of this.sources)if(source.stopAt<=this.currentTime&&source.onended)source.onended();}
}
function setup(t){const context=new Context(),audio=new GameAudio(context);t.after(()=>audio.dispose());return {context,audio};}

test('sound graph cleans up every transient even when disposed before a scheduled cue starts',t=>{
  const {context,audio}=setup(t);
  audio.play('legendary');assert.ok(audio.nodes.size>8);
  context.advance(3);assert.equal(audio.nodes.size,0);assert.equal(audio.voices.size,0);
  audio.play('round-complete');const sources=[...audio.nodes];assert.ok(sources.some(source=>source.startAt>context.currentTime));
  audio.dispose();assert.equal(audio.timer,null);assert.equal(audio.nodes.size,0);assert.equal(audio.voices.size,0);
  assert.ok(sources.every(source=>source.disconnected&&source.onended===null));
  assert.ok(context.allNodes.slice(1).every(node=>node.disconnected));
  const count=context.sources.length;audio.schedule();audio.play('shot');audio.setActive(true);audio.update(.1);
  assert.equal(context.sources.length,count);assert.equal(audio.room.buffer,null);assert.equal(audio.noise,null);
  audio.dispose(); // Unmount/blur races may dispose more than once.
});

test('music cannot consume the effect voice reserve and gun fire stays bounded under saturation',t=>{
  const {context,audio}=setup(t);
  for(let i=0;i<200;i++)audio.voice({bus:audio.music,duration:2});
  assert.equal(audio.nodes.size,audio.musicVoiceLimit);
  const musicCount=[...audio.voices.values()].filter(voice=>voice.music).length;
  audio.play('shot',{family:'SMG'});assert.ok(audio.nodes.size>musicCount);
  for(let i=0;i<200;i++)audio.play('shot',{family:'shotgun'});
  assert.equal(audio.nodes.size,audio.voiceLimit);
  assert.equal([...audio.voices.values()].filter(voice=>voice.music).length,0,'saturated effects evict music before rejecting further effects');
  context.advance(5);assert.equal(audio.nodes.size,0);
});

test('suspended audio and inactive music never schedule a backlog after a long pause',t=>{
  const {context,audio}=setup(t);
  audio.schedule();assert.equal(audio.nodes.size,0);
  context.state='suspended';audio.setActive(true);audio.play('shot');audio.schedule();assert.equal(audio.nodes.size,0);
  context.currentTime=3600;context.state='running';audio.schedule();
  assert.ok(audio.step<=2);assert.ok(context.sources.every(source=>source.startAt>=3600&&source.startAt<3601));
  const count=context.sources.length;audio.setActive(false);context.advance(5);audio.schedule();
  assert.equal(context.sources.length,count);assert.equal(audio.music.gain.value,0);
});

test('independent mixes are bounded and event ducking restores the requested music volume',t=>{
  const {context,audio}=setup(t);
  audio.setVolume(2);audio.setMix(-1,2);assert.equal(audio.masterVolume,1);assert.equal(audio.effectsVolume,1);assert.equal(audio.musicVolume,0);
  audio.setMix(.62,.45);audio.setActive(true);audio.play('boss-kill');
  assert.equal(audio.music.gain.value,.62);assert.equal(audio.fx.gain.value,.45);assert.equal(audio.musicDuck.gain.value,.4);
  context.advance(2);audio.update(.1);assert.equal(audio.musicDuck.gain.value,1);assert.equal(audio.music.gain.value,.62);
});

test('boss, director pressure, blackout and recovery adapt the score without triggering duplicate stingers',t=>{
  const {context,audio}=setup(t);audio.setActive(true);
  for(let i=0;i<20;i++)audio.update(.1,{enemies:25,pressure:1,boss:{phase:3},healthRatio:.15,event:{id:'blackout'}});
  assert.equal(audio.bossPhase,3);assert.ok(audio.intensity>.98);assert.equal(audio.scoreFilter.frequency.value,950);assert.equal(audio.healthRatio,.15);
  assert.equal(context.sources.length,0,'state updates change mix without scheduling reward cues');
  for(let i=0;i<40;i++)audio.update(.1,{enemies:0,pressure:0,boss:false,event:null,healthRatio:1});
  assert.equal(audio.bossPhase,0);assert.ok(audio.intensity<.01);assert.ok(audio.scoreFilter.frequency.value>3000);
});

test('shotgun, sniper and SMG have distinct attack/tail envelopes and legacy shots accept no config',t=>{
  const {context,audio}=setup(t);
  const capture=weapon=>{const start=context.sources.length;audio.play('shot',weapon);const voices=context.sources.slice(start);context.advance(1);return voices;};
  const smg=capture({family:'SMG'}),shotgun=capture({family:'shotgun'}),sniper=capture({family:'sniper'});
  const maxLength=voices=>Math.max(...voices.map(voice=>voice.stopAt-voice.startAt));
  assert.ok(maxLength(smg)<maxLength(shotgun));assert.ok(maxLength(shotgun)<maxLength(sniper));
  assert.ok(shotgun.length>smg.length);assert.ok(sniper.length>shotgun.length);
  assert.ok(capture(null).length>=3);
});

test('reward aliases produce distinctive tonal cues while duplicate crowd hits are consolidated',t=>{
  const {context,audio}=setup(t);
  for(const cue of ['loot','legendary-drop','mythic','power-up','boss-start','boss-phase','boss-killed','round-start','round-complete','multikill','headshot','forge','elite','spawn-warning','reload-insert','reload-chamber','shell']){
    const before=context.sources.length;audio.play(cue);assert.ok(context.sources.length>before,`${cue} creates voices`);context.advance(2);
  }
  audio.play('headshot');const once=context.sources.length;audio.play('critical');assert.equal(context.sources.length,once);
  context.advance(.08);audio.play('headshot');assert.ok(context.sources.length>once);
});
