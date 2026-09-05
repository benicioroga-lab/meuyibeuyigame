import {WEAPONS,WEAPON_UPGRADES,DOG_UPGRADES,ECONOMY} from './config.js';

const statLine=(name,before,after)=>`<div class="upgrade-delta"><span>${name}</span><b>${before}</b><i>→</i><strong>${after}</strong></div>`;
const money=value=>value.toLocaleString('pt-BR');
const fixed=value=>Number(value.toFixed(2));
const effectNames={kinetic:'PRECISÃO',pierce:'PERFURAÇÃO',burn:'INCENDIÁRIA',chain:'CHOQUE EM CADEIA',frost:'ÁREA + LENTIDÃO'};

export function createShop({state,roundState,combat,dog,legacyUpgrades,buyLegacy,toast,updateUI}){
  let tab='weapons';
  const root=document.getElementById('upgradeList');
  const playerIds=['speed','jump','dash','bark','armor','regen','magnet','luck','dig','secret'];
  const comparisons={
    speed:level=>['Velocidade',`${fixed(5.6+level*.42)} m/s`],jump:level=>['Impulso do pulo',`${fixed(9.2+level*.8)} m/s`],
    dash:level=>['Recarga do dash',`${fixed(Math.max(.28,1.05-level*.085))}s`],bark:level=>['Alcance do latido',`${fixed(3.4+level*.45)} m`],
    armor:level=>['Redução de dano',`${Math.round((1-1/(1+level*.18))*100)}%`],regen:level=>['Recuperação',`${fixed(level*.38)} HP/s`],
    magnet:level=>['Raio de coleta',`${fixed(1.75+level*.46)} m`],luck:level=>['Bônus de petiscos',`${Math.round(level*12)}%`],
    dig:level=>['Recompensa por tesouro',`${70+level*22}`],secret:level=>['Cura do petisco verde',`${22+level*3} HP`],
  };
  function costButton(action,id,cost,{locked=false,label='',max=false}={}){
    return `<button class="purchase-button" data-action="${action}" data-id="${id}" ${locked||max||cost!==null&&state.coins<cost?'disabled':''}>${label|| (max?'MÁXIMO':`◈ ${money(cost)}`)}</button>`;
  }
  function weapons(){
    const arsenal=combat.arsenal,current=arsenal.stats();
    const cards=WEAPONS.map(config=>{
      const owned=arsenal.inventory.has(config.id),equipped=config.id===arsenal.currentId,locked=roundState.round<config.unlockRound,stats=arsenal.stats(config.id);
      return `<article class="weapon-card ${equipped?'equipped':''} ${locked?'locked':''}" style="--weapon-color:${config.color}"><div class="weapon-card-top"><span>${config.category}</span><small>${equipped?'EM USO':owned?'NO INVENTÁRIO':`ROUND ${config.unlockRound}`}</small></div><div class="weapon-illustration" aria-hidden="true"><i></i><b></b><span></span></div><h3>${config.name}</h3><p>${config.description}</p><div class="weapon-stat-grid"><span>DANO<b>${stats.damage}</b></span><span>TIROS/S<b>${stats.fireRate}</b></span><span>PENTE<b>${stats.magazineSize}</b></span><span>RELOAD<b>${stats.reloadTime}s</b></span></div><span class="effect-tag">${effectNames[config.effect]}</span>${!owned&&!locked?`<div class="weapon-comparison">Arma atual → esta arma${statLine('Dano',current.damage,stats.damage)}${statLine('Pente',current.magazineSize,stats.magazineSize)}</div>`:''}${owned?costButton('equip',config.id,null,{max:equipped,label:equipped?'EQUIPADA':'EQUIPAR'}):costButton('weapon',config.id,config.price,{locked,label:locked?`LIBERA NO ROUND ${config.unlockRound}`:''})}</article>`;
    }).join('');
    const modifications=Object.entries(WEAPON_UPGRADES).map(([id,config])=>{
      const cost=arsenal.upgradeCost(id),next=arsenal.nextStats(id);const key=id==='damage'?'damage':id==='magazine'?'magazineSize':'reloadTime';
      return `<article class="training-card"><h3>${config.name}<small>${arsenal.current.upgrades[id]} / ${config.max}</small></h3>${statLine(id==='damage'?'Dano':id==='magazine'?'Capacidade':'Recarga',current[key]+(id==='reload'?'s':''),next?next[key]+(id==='reload'?'s':''):'MAX')}${costButton('weapon-upgrade',id,cost,{max:cost===null})}</article>`;
    }).join('');
    return `<div class="shop-section-title"><div><span>SEU EQUIPAMENTO</span><h3>${current.name}</h3></div><button class="supply-button" data-action="ammo">Repor reserva · ◈ ${ECONOMY.ammoShopBase+roundState.round*ECONOMY.ammoShopRoundScale}</button></div><div class="training-grid weapon-mods">${modifications}</div><div class="shop-section-title"><div><span>PRÓXIMO PASSO</span><h3>Um novo jeito de jogar.</h3></div><small>Compras incluem munição inicial.</small></div><div class="weapon-catalog">${cards}</div>`;
  }
  function dogs(){
    const training=dog.training,current=training.stats();
    const fields={bite:['Dano','damage',''],tempo:['Tempo entre ataques','attackCooldown','s'],agility:['Velocidade','speed',' m/s'],guard:['Vida','health',' HP'],instinct:['Crítico','criticalChance','%'],pack:['Alvos por ataque','targets',''],element:['Poder especial','element','']};
    const stages=['Mordida','Choque + stun','Choque + lentidão','Execução + onda'];
    return `<div class="dog-shop-intro"><span class="dog-shop-emblem">🐾</span><div><span>SEU PARCEIRO · NÍVEL ${current.level}</span><h3>Faro cresce com você.</h3><p>Ele caça, protege e volta quando você chama. <kbd>C</kbd> alterna caçar / seguir.</p></div><button class="supply-button" data-action="dog-heal">Cuidar do Faro · ◈ 40</button></div><div class="training-grid">${Object.entries(DOG_UPGRADES).map(([id,config])=>{
      const next=training.next(id),cost=training.cost(id),unlock=training.unlock(id),locked=roundState.round<unlock,[label,key,suffix]=fields[id];
      const display=value=>id==='element'?stages[value]:id==='instinct'?Math.round(value*100)+suffix:fixed(value)+suffix;
      return `<article class="training-card"><h3>${config.name}<small>${training.levels[id]} / ${config.max}</small></h3><p>${config.description}</p>${statLine(label,display(current[key]),next?display(next[key]):'MAX')}${id==='guard'&&next?statLine('Resistência',Math.round(current.resistance*100)+'%',Math.round(next.resistance*100)+'%'):''}${costButton('dog',id,cost,{max:cost===null,locked,label:locked?`ROUND ${unlock}`:''})}</article>`;
    }).join('')}</div>`;
  }
  function player(){return `<div class="shop-section-title"><div><span>O HERÓI DO CALÇADÃO</span><h3>Mais fôlego para o caos.</h3></div></div><div class="training-grid">${legacyUpgrades.filter(u=>playerIds.includes(u.id)).map(u=>{const level=state.upgrades[u.id],cost=Math.round(u.base*Math.pow(1.52,level)),[label,before]=comparisons[u.id](level),[,after]=comparisons[u.id](level+1);return `<article class="training-card"><h3>${u.title}<small>${level} / 5</small></h3><p>${u.desc}</p>${statLine(label,before,level<5?after:'MAX')}${costButton('player',u.id,cost,{max:level>=5})}</article>`;}).join('')}</div>`;}
  function render(){
    const scroll=root.parentElement.scrollTop;
    document.getElementById('drawerCoins').textContent=money(state.coins);root.classList.add('progression-shop');
    root.innerHTML=`<nav class="shop-tabs" aria-label="Categorias de melhorias">${[['weapons','ARSENAL'],['dog','FARO'],['player','MEYUI']].map(([id,label])=>`<button data-action="tab" data-id="${id}" aria-pressed="${tab===id}">${label}</button>`).join('')}</nav><section class="shop-content">${tab==='weapons'?weapons():tab==='dog'?dogs():player()}</section>`;
    root.parentElement.scrollTop=scroll;
  }
  root.addEventListener('click',event=>{
    const button=event.target.closest('button[data-action]');if(!button||button.disabled)return;
    const {action,id}=button.dataset;if(action==='tab'){tab=id;render();return;}
    let success=false;
    if(action==='weapon')success=combat.arsenal.buy(id,state,roundState.round);
    if(action==='equip')success=combat.arsenal.equip(id);
    if(action==='ammo')success=combat.arsenal.refill(state,roundState.round);
    if(action==='weapon-upgrade')success=combat.arsenal.upgrade(id,state);
    if(action==='dog')success=dog.upgrade(id,state,roundState.round);
    if(action==='dog-heal')success=dog.heal(state);
    if(action==='player'&&playerIds.includes(id)&&state.upgrades[id]<5){const old=state.upgrades[id];buyLegacy(id);success=state.upgrades[id]>old;}
    if(success){if(action==='weapon')toast(`${combat.arsenal.stats().name} equipada. Bora testar.`);updateUI();render();root.querySelector(`[data-action="${action}"][data-id="${id||''}"]`)?.focus({preventScroll:true});}
    else if(action==='ammo')toast(combat.arsenal.current.reserve===combat.arsenal.stats().maxReserve?'Sua reserva já está cheia.':'Faltam petiscos para repor munição.');
    else if(action==='dog-heal')toast('Faro está bem ou faltam petiscos.');
  });
  return {render};
}
