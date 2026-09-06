// Only this game's key is read or written. No account or machine credentials are used.
const VERSION=2;
const DEFAULT_KEY='meyui-beuyi:progression:v2';
const bounded=(value,max=1e9)=>Number.isFinite(Number(value))?Math.max(0,Math.min(max,Math.floor(Number(value)))):0;
const copy=value=>JSON.parse(JSON.stringify(value));
const textId=value=>typeof value==='string'?value.slice(0,120):'';
const finiteMultiplier=value=>Math.min(1.2,Math.max(.8,value));
export const META_UPGRADES=Object.freeze({
  supplies:{name:'Reserva de expedição',description:'+10% de munição inicial por nível. O limite da reserva continua valendo.',cost:3,max:2,branch:'preparation'},
  conditioning:{name:'Fôlego de rua',description:'+5% de vida inicial por nível.',cost:4,max:2,branch:'preparation'},
  companion:{name:'Confiança do Faro',description:'+10% de vida do Faro por nível.',cost:3,max:2,branch:'preparation'},
  cascade:{name:'Licença: Cascata',description:'Permite começar com a escopeta Cascata.',cost:7,max:1,branch:'loadout',weaponId:'cascade'},
  horizon:{name:'Licença: Horizonte',description:'Permite começar com o rifle de precisão Horizonte.',cost:10,max:1,branch:'loadout',weaponId:'horizon'},
  firefly:{name:'Licença: Vagalume',description:'Permite começar com a SMG Vagalume.',cost:8,max:1,branch:'loadout',weaponId:'firefly'},
  prism:{name:'Contato: Prisma',description:'Libera peças Prisma nas opções de equipamento inicial e da loja.',cost:5,max:1,branch:'options',manufacturer:'prisma',attachments:['shockcell','cryocell']},
  foundry:{name:'Contato: Fundição',description:'Libera munição corrosiva e cano de fornalha como opções iniciais.',cost:5,max:1,branch:'options',manufacturer:'fundicao',attachments:['acidcell','furnace']},
  precision:{name:'Oficina de precisão',description:'Libera mira de precisão e receptor de rajada no equipamento inicial.',cost:4,max:1,branch:'options',attachments:['marksman','burst']},
  scout:{name:'Especialização: Batedor',description:'Opção de personagem: +4% de movimento e −5% de vida.',cost:5,max:1,branch:'options',character:'scout'},
  keeper:{name:'Especialização: Guardião',description:'Opção de personagem: Faro com +8% de vida e −5% de munição inicial.',cost:5,max:1,branch:'options',character:'keeper'},
  copper:{name:'Coleção cobre',description:'Acabamento cobre para a coleira e o equipamento do Faro.',cost:3,max:1,branch:'cosmetic',skin:'copper'},
  midnight:{name:'Coleção meia-noite',description:'Acabamento azul para a coleira e o equipamento do Faro.',cost:5,max:1,branch:'cosmetic',skin:'midnight'},
  chaos:{name:'Indutor de Caos',description:'Libera o próximo nível de Chaos. Aumenta risco e recompensa; não aumenta seu poder inicial.',cost:6,max:4,branch:'challenge'},
});
export const ACHIEVEMENTS=Object.freeze({
  first_boss:{name:'Derruba-portões',description:'Derrote seu primeiro boss.',shards:3,metric:'bosses',target:1},
  round_10:{name:'Só mais um round',description:'Conclua o round 10.',shards:4,metric:'bestRound',target:10},
  round_25:{name:'Dono da madrugada',description:'Conclua o round 25.',shards:7,metric:'bestRound',target:25},
  precision:{name:'Mira de respeito',description:'Acerte 25 eliminações por headshot em uma partida.',shards:3,metric:'runHeadshots',target:25},
  good_dog:{name:'Dupla de respeito',description:'Faro elimina 50 inimigos ao longo das partidas.',shards:3,metric:'dogKills',target:50},
  explorer:{name:'Cada beco conta',description:'Abra 12 baús ao longo das partidas.',shards:3,metric:'chests',target:12},
});
export const RUN_CHALLENGES=Object.freeze({
  scavenger:{name:'Garimpo',description:'Abra 3 baús nesta partida.',metric:'chests',target:3,shards:1},
  partner:{name:'Trabalho em dupla',description:'Faro elimina 10 inimigos nesta partida.',metric:'dogKills',target:10,shards:1},
  clean:{name:'Nem um arranhão',description:'Conclua um round a partir do 5 sem receber dano.',metric:'cleanRound',target:1,shards:2},
});
const DEFAULT_LOADOUT={weaponId:'biscuit',attachmentId:null,skin:'default',character:'meyui',region:'lower'};
const DEFAULT_STATS={runs:0,kills:0,headshots:0,dogKills:0,bosses:0,chests:0,gates:0,shardsEarned:0,bestRound:0,bestScore:0,bestChaos:0};
const freshState=()=>({version:VERSION,shards:0,upgrades:{},achievements:[],ledger:[],stats:{...DEFAULT_STATS},loadout:{...DEFAULT_LOADOUT},maxChaos:1});
function browserStorage(){try{return globalThis.localStorage||null;}catch{return null;}}
function sanitize(raw){
  const state=freshState();if(!raw||typeof raw!=='object'||Array.isArray(raw))return state;
  // Version 1 kept crystals and bestRound at top level. Import only known, bounded fields.
  state.shards=bounded(raw.shards??raw.crystals,1e7);
  for(const [id,config] of Object.entries(META_UPGRADES))state.upgrades[id]=bounded(raw.upgrades?.[id],config.max);
  for(const id of Object.keys(DEFAULT_STATS))state.stats[id]=bounded(raw.stats?.[id]??(id==='bestRound'?raw.bestRound:0));
  state.achievements=Array.isArray(raw.achievements)?[...new Set(raw.achievements.filter(id=>Object.hasOwn(ACHIEVEMENTS,id)))]:[];
  state.ledger=Array.isArray(raw.ledger)?[...new Set(raw.ledger.filter(id=>typeof id==='string').map(id=>id.slice(0,180)))].slice(-512):[];
  if(raw.loadout&&typeof raw.loadout==='object')for(const key of Object.keys(DEFAULT_LOADOUT))state.loadout[key]=raw.loadout[key]===null?null:textId(raw.loadout[key]);
  state.maxChaos=1+state.upgrades.chaos;return state;
}
export class MetaProgression {
  constructor({storage=browserStorage(),key=DEFAULT_KEY,onChange=()=>{},runId}={}){
    this.storage=storage;this.key=key;this.onChange=onChange;this.memory=null;this.storageAvailable=!!storage;this.pendingNotifications=[];this.state=freshState();this.load();this.beginRun({runId:runId||`run:${Date.now()}:${Math.random().toString(36).slice(2,9)}`});
  }
  load(){let raw=this.memory;try{raw=this.storage?.getItem(this.key)??this.memory;}catch{this.storageAvailable=false;}try{this.state=sanitize(raw?JSON.parse(raw):null);}catch{this.state=freshState();this.storageAvailable=false;}this.validateLoadout();return this.state;}
  save(){this.state.version=VERSION;const serialized=JSON.stringify(this.state);this.memory=serialized;try{this.storage?.setItem(this.key,serialized);}catch{this.storageAvailable=false;}try{this.onChange(this.getMenuData());}catch{}return this.state;}
  beginRun({runId}={}){this.runId=textId(runId)||`run:${Date.now()}:${Math.random().toString(36).slice(2,9)}`;this.run={kills:0,headshots:0,dogKills:0,chests:0,gates:0,cleanRound:0,round:0,damageTaken:0,purchases:0,bosses:0};this.runChallenges=new Set();this.ended=false;return this.runId;}
  once(id){if(this.state.ledger.includes(id))return false;this.state.ledger.push(id);if(this.state.ledger.length>512)this.state.ledger.splice(0,this.state.ledger.length-512);return true;}
  addShards(amount,reason){const value=bounded(amount,1000);this.state.shards=Math.min(1e7,this.state.shards+value);this.state.stats.shardsEarned+=value;if(value)this.pendingNotifications.push({kind:'shards',name:reason,amount:value});return value;}
  award(reason,data={}){
    const runId=textId(data.runId)||this.runId,round=bounded(data.round),token=textId(data.encounterId||data.id||data.bossId);
    let amount=0,key='';
    if(reason==='boss'){key=`boss:${runId}:${token||`round:${round}`}`;amount=2+Math.min(4,Math.floor(round/15));}
    else if(reason==='milestone'){if(round<5||round%5!==0)return 0;key=`milestone:${runId}:${round}`;amount=1+Math.min(3,Math.floor(round/25));}
    else if(reason==='challenge'){const challenge=RUN_CHALLENGES[data.challengeId];if(!challenge||(this.run[challenge.metric]||0)<challenge.target)return 0;key=`challenge:${runId}:${data.challengeId}`;amount=challenge.shards;}
    else return 0;
    if(!this.once(key))return 0;
    if(reason==='boss'){this.run.bosses++;this.state.stats.bosses++;}
    if(reason==='milestone')this.state.stats.bestRound=Math.max(this.state.stats.bestRound,round);
    this.addShards(amount,reason==='boss'?'Boss derrotado':reason==='milestone'?`Round ${round}`:'Desafio concluído');this.checkAchievements();this.save();return amount;
  }
  record(kind,data=1){
    const value=typeof data==='number'?{amount:data}:data||{},amount=bounded(value.amount??1,10000);if(this.ended)return;
    if(kind==='kill'){this.run.kills+=amount;this.state.stats.kills+=amount;if(value.headshot){this.run.headshots+=amount;this.state.stats.headshots+=amount;}if(value.source==='dog'){this.run.dogKills+=amount;this.state.stats.dogKills+=amount;}}
    else if(kind==='chest'||kind==='gate'){const metric=kind==='chest'?'chests':'gates';this.run[metric]+=amount;this.state.stats[metric]+=amount;}
    else if(kind==='damage')this.run.damageTaken+=Math.max(0,Number(value.amount)||0);
    else if(kind==='purchase')this.run.purchases+=amount;
    else if(kind==='round'||kind==='roundComplete'){
      const round=bounded(value.round??value.amount);this.run.round=Math.max(this.run.round,round);this.state.stats.bestRound=Math.max(this.state.stats.bestRound,round);
      if(round>=5&&value.damageTaken===0)this.run.cleanRound=1;
    }
    const achievementCount=this.state.achievements.length;this.checkAchievements();for(const [id,challenge] of Object.entries(RUN_CHALLENGES))if(this.run[challenge.metric]>=challenge.target&&!this.runChallenges.has(id)){this.runChallenges.add(id);this.award('challenge',{challengeId:id});}
    // Frequent kill events stay in memory; milestones, menu purchases and endRun flush progress.
    if(kind!=='kill'||this.run.kills%10===0||this.state.achievements.length!==achievementCount)this.save();
  }
  checkAchievements(){
    const metrics={...this.state.stats,runHeadshots:this.run?.headshots||0};
    for(const [id,achievement] of Object.entries(ACHIEVEMENTS))if(!this.state.achievements.includes(id)&&metrics[achievement.metric]>=achievement.target){this.state.achievements.push(id);this.addShards(achievement.shards,achievement.name);this.pendingNotifications.push({kind:'achievement',id,name:achievement.name});}
  }
  endRun(summary={}){
    const runId=textId(summary.runId)||this.runId;if(!this.once(`end:${runId}`))return this.getMenuData();this.ended=true;this.state.stats.runs++;
    this.state.stats.bestRound=Math.max(this.state.stats.bestRound,bounded(summary.completedRound??summary.completedRounds??summary.round??this.run.round));this.state.stats.bestScore=Math.max(this.state.stats.bestScore,bounded(summary.score));this.state.stats.bestChaos=Math.max(this.state.stats.bestChaos,bounded(summary.chaos,5));
    this.checkAchievements();this.save();return this.getMenuData();
  }
  cost(id){const config=META_UPGRADES[id];if(!config)return null;const level=this.state.upgrades[id]||0;return level>=config.max?null:config.cost*(level+1);}
  purchase(id){const cost=this.cost(id);if(cost===null||this.state.shards<cost)return false;this.state.shards-=cost;this.state.upgrades[id]=(this.state.upgrades[id]||0)+1;this.state.maxChaos=1+(this.state.upgrades.chaos||0);this.pendingNotifications.push({kind:'unlock',id,name:META_UPGRADES[id].name});this.save();return true;}
  getLoadoutOptions(){
    const options={weaponIds:['biscuit'],manufacturers:['faisca','muralha','agulha','remendo'],attachmentIds:['dot','balanced'],skins:['default'],characters:['meyui'],regions:['lower'],difficulties:['easy','normal','hard','insane','nightmare'],maxChaos:this.state.maxChaos};
    for(const [id,config] of Object.entries(META_UPGRADES))if(this.state.upgrades[id]>0){if(config.weaponId)options.weaponIds.push(config.weaponId);if(config.manufacturer)options.manufacturers.push(config.manufacturer);if(config.attachments)options.attachmentIds.push(...config.attachments);if(config.skin)options.skins.push(config.skin);if(config.character)options.characters.push(config.character);}
    return options;
  }
  getRunBonuses(){const levels=this.state.upgrades,loadout=this.state.loadout,character=loadout.character;return {maxHealthMultiplier:finiteMultiplier((1+(levels.conditioning||0)*.05)*(character==='scout'?.95:1)),startingAmmoMultiplier:finiteMultiplier((1+(levels.supplies||0)*.1)*(character==='keeper'?.95:1)),dogHealthMultiplier:finiteMultiplier((1+(levels.companion||0)*.1)*(character==='keeper'?1.08:1)),movementMultiplier:character==='scout'?1.04:1,dogDamageMultiplier:1,startingWeaponId:loadout.weaponId,startingAttachmentId:loadout.attachmentId,skin:loadout.skin,skinColor:loadout.skin==='copper'?'#d49362':loadout.skin==='midnight'?'#80b4df':null,character,startingRegion:loadout.region,metaUnlocks:this.getLoadoutOptions()};}
  validateLoadout(){const options=this.getLoadoutOptions(),keys={weaponId:'weaponIds',attachmentId:'attachmentIds',skin:'skins',character:'characters',region:'regions'};for(const [key,list] of Object.entries(keys))if(!(key==='attachmentId'&&this.state.loadout[key]===null)&&!options[list].includes(this.state.loadout[key]))this.state.loadout[key]=DEFAULT_LOADOUT[key];}
  selectLoadout(selection={}){const before={...this.state.loadout};for(const key of Object.keys(DEFAULT_LOADOUT))if(Object.hasOwn(selection,key))this.state.loadout[key]=selection[key];this.validateLoadout();const accepted=Object.keys(selection).every(key=>Object.hasOwn(DEFAULT_LOADOUT,key)&&this.state.loadout[key]===selection[key]);if(!accepted){this.state.loadout=before;return false;}this.save();return true;}
  drainNotifications(){return this.pendingNotifications.splice(0);}
  getMenuData(){return {shards:this.state.shards,stats:{...this.state.stats},loadout:{...this.state.loadout},options:this.getLoadoutOptions(),maxChaos:this.state.maxChaos,storageAvailable:this.storageAvailable,upgrades:Object.entries(META_UPGRADES).map(([id,config])=>({id,...config,level:this.state.upgrades[id]||0,cost:this.cost(id),owned:(this.state.upgrades[id]||0)>=config.max})),achievements:Object.entries(ACHIEVEMENTS).map(([id,config])=>({id,...config,complete:this.state.achievements.includes(id),progress:Math.min(config.target,config.metric==='runHeadshots'?this.run?.headshots||0:this.state.stats[config.metric]||0)})),challenges:Object.entries(RUN_CHALLENGES).map(([id,config])=>({id,...config,progress:Math.min(config.target,this.run?.[config.metric]||0),complete:this.runChallenges?.has(id)||false}))};}
  snapshot(){return copy(this.state);}
}
