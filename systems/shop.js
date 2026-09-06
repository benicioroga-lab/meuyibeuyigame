import {WEAPON_UPGRADES,DOG_UPGRADES,ECONOMY} from './config.js';
import {LOOT_WEAPONS,RARITIES,MANUFACTURERS,ATTACHMENTS,SLOT_NAMES,ELEMENTS,LEGENDARY_PERKS,FORGE_MAX_TIER,INVENTORY_LIMIT} from './loot-config.js';
import {compareWeapons} from './weapon-rolls.js';
import {DOG_TALENTS} from './dog.js';

export const escapeHTML=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const money=value=>Math.max(0,Math.round(Number(value)||0)).toLocaleString('pt-BR');
const fixed=value=>Number(Number(value||0).toFixed(2));
const statLine=(name,before,after)=>`<div class="upgrade-delta"><span>${escapeHTML(name)}</span><b>${escapeHTML(before)}</b><i>→</i><strong>${escapeHTML(after)}</strong></div>`;
const rarityFor=stats=>RARITIES[stats.rarity]||RARITIES.common;
const effectNames={kinetic:'Cinético',pierce:'Perfuração',burn:'Fogo',chain:'Choque',frost:'Gelo',corrosive:'Corrosivo',explosive:'Explosivo'};
const elementsFor=stats=>ELEMENTS[stats.element]?.name||effectNames[stats.effect]||'Cinético';
const statValue=(key,value)=>key==='criticalChance'?`${Math.round(value*100)}%`:key==='criticalMultiplier'?`${fixed(value)}×`:key==='reloadTime'?`${fixed(value)}s`:key==='fireRate'?`${Math.round(value*60)} RPM`:String(fixed(value));

export function comparisonHTML(current,next,{compact=false}={}){
  if(!current||!next)return '';
  const rows=compareWeapons(current,next).filter(row=>!compact||['damage','fireRate','magazineSize','reloadTime','criticalChance'].includes(row.key));
  const format=(row,value)=>row.key==='criticalChance'?`${fixed(value)}%`:statValue(row.key,value);
  return `<div class="roll-comparison"><div class="comparison-heading"><span>EQUIPADA</span><strong>NOVA CONFIGURAÇÃO</strong></div>${rows.map(row=>`<div class="comparison-row ${row.delta===0?'same':row.better?'better':'worse'}"><span>${escapeHTML(row.label)}</span><b>${escapeHTML(format(row,row.before))}</b><i aria-label="${row.delta===0?'igual':row.better?'melhora':'reduz'}">${row.delta===0?'=':row.better?'↑':'↓'}</i><strong>${escapeHTML(format(row,row.after))}</strong></div>`).join('')}</div>`;
}

export function createShop({state,roundState,combat,dog,legacyUpgrades=[],buyLegacy=()=>{},toast=()=>{},updateUI=()=>{},getDirector=()=>null,getMeta=()=>null,world=null,requireStation=true}){
  let tab='weapons',station=null,selectedId=null,partSlot='scope',manufacturer='faisca';
  const root=document.getElementById('upgradeList');
  const playerIds=['speed','jump','dash','bark','armor','regen','magnet','luck','dig','secret'];
  const comparisons={
    speed:level=>['Velocidade',`${fixed(5.6+level*.42)} m/s`],jump:level=>['Impulso do pulo',`${fixed(9.2+level*.8)} m/s`],
    dash:level=>['Recarga do dash',`${fixed(Math.max(.28,1.05-level*.085))}s`],bark:level=>['Alcance do latido',`${fixed(3.4+level*.45)} m`],
    armor:level=>['Redução de dano',`${Math.round((1-1/(1+level*.18))*100)}%`],regen:level=>['Recuperação',`${fixed(level*.38)} HP/s`],
    magnet:level=>['Raio de coleta',`${fixed(1.75+level*.46)} m`],luck:level=>['Bônus de petiscos',`${Math.round(level*12)}%`],
    dig:level=>['Recompensa por tesouro',`${70+level*22}`],secret:level=>['Cura do petisco verde',`${22+level*3} HP`],
  };
  const arsenal=combat.arsenal;
  function button(action,id,cost,{locked=false,label='',max=false,title=''}={}){
    return `<button class="purchase-button" data-action="${action}" data-id="${escapeHTML(id)}" ${locked||max||cost!==null&&state.coins<cost?'disabled':''} ${title?`title="${escapeHTML(title)}"`:''}>${escapeHTML(label||(max?'MÁXIMO':`◈ ${money(cost)}`))}</button>`;
  }
  function info(stats){
    const rarity=rarityFor(stats),perk=LEGENDARY_PERKS[stats.perk];
    return `<div class="weapon-card-top"><span>${escapeHTML(stats.category)}</span><small>${rarity.symbol} ${rarity.name.toUpperCase()}</small></div><div class="weapon-illustration ${escapeHTML(stats.family||'')}" aria-hidden="true"><i></i><b></b><span></span></div><h3>${escapeHTML(stats.name)}</h3><p class="weapon-manufacturer">${escapeHTML(stats.manufacturerName||MANUFACTURERS[stats.manufacturer]?.name||'Oficina da base')} · ${elementsFor(stats)}</p><div class="weapon-stat-grid"><span>DANO / DISPARO<b>${fixed(stats.damage)}${stats.pellets>1?`<small class="pellet-caption">TOTAL · ${stats.pellets} PROJÉTEIS</small>`:''}</b></span><span>CADÊNCIA<b>${Math.round(stats.fireRate*60)} <small>RPM</small></b></span><span>PENTE<b>${stats.magazineSize}</b></span><span>RECARGA<b>${fixed(stats.reloadTime)}s</b></span></div>${perk?`<p class="legendary-trait"><b>★ ${escapeHTML(perk.name)}</b>${escapeHTML(perk.description)}</p>`:''}`;
  }
  function partsList(entry,editable=false){return `<ul class="fitted-parts">${Object.entries(entry?.roll?.attachments||{}).map(([slot,part])=>`<li><span>${escapeHTML(SLOT_NAMES[slot]||slot)}</span><b>${escapeHTML(ATTACHMENTS[part.id]?.name||part.id)}</b><small>${escapeHTML(MANUFACTURERS[part.manufacturer]?.name||'')}</small>${editable?`<button class="part-remove" data-action="remove-part" data-id="${slot}" ${arsenal.attachmentStash.size>=40?'disabled':''}>RETIRAR PARA A BOLSA</button>`:''}</li>`).join('')||'<li class="muted">Sem peças instaladas. Personalize na aba Peças.</li>'}</ul>`;}
  function weapons(){
    const current=arsenal.stats();
    const modifications=Object.entries(WEAPON_UPGRADES).map(([id,config])=>{
      const cost=arsenal.upgradeCost(id),next=arsenal.nextStats(id),key=id==='damage'?'damage':id==='magazine'?'magazineSize':'reloadTime';
      return `<article class="training-card"><h3>${escapeHTML(config.name)}<small>${arsenal.current.upgrades[id]} / ${config.max}</small></h3>${statLine(id==='damage'?'Dano':id==='magazine'?'Capacidade':'Recarga',statValue(key,current[key]),next?statValue(key,next[key]):'MAX')}${button('weapon-upgrade',id,cost,{max:cost===null})}</article>`;
    }).join('');
    const cards=LOOT_WEAPONS.map(config=>{
      const entry=arsenal.current.baseId===config.id?arsenal.current:[...arsenal.inventory.values()].find(entry=>(entry.baseId||entry.id)===config.id),owned=Boolean(entry),equipped=entry?.id===arsenal.currentId,locked=roundState.round<config.unlockRound,stats=owned?arsenal.stats(entry.id):arsenal.stats(config.id),rarity=rarityFor(stats);
      return `<article class="weapon-card ${equipped?'equipped':''} ${locked?'locked':''}" style="--weapon-color:${rarity.color}">${info(stats)}<p>${escapeHTML(config.description)}</p>${!owned&&!locked?comparisonHTML(current,stats,{compact:true}):''}${owned?button('equip',entry.id,null,{max:equipped,label:equipped?'EQUIPADA':'EQUIPAR EXISTENTE'}):button('weapon',config.id,arsenal.buyCost?.(config.id)??config.price,{locked:locked||arsenal.inventory.size>=INVENTORY_LIMIT,label:locked?`LIBERA NO ROUND ${config.unlockRound}`:arsenal.inventory.size>=INVENTORY_LIMIT?'INVENTÁRIO CHEIO':''})}</article>`;
    }).join('');
    return `<div class="shop-section-title"><div><span>ABASTECIMENTO</span><h3>${escapeHTML(current.name)}</h3></div><button class="supply-button" data-action="ammo">Repor reserva · ◈ ${arsenal.refillCost?.(roundState.round)??ECONOMY.ammoShopBase+roundState.round*ECONOMY.ammoShopRoundScale}</button></div><div class="training-grid weapon-mods">${modifications}</div><div class="shop-section-title"><div><span>ARMAS DE BASE</span><h3>Escolha o próximo passo.</h3></div><small>Rolls e raridades especiais são encontrados explorando.</small></div><div class="weapon-catalog">${cards}</div>`;
  }
  function inventory(){
    if(!arsenal.inventory.has(selectedId))selectedId=arsenal.currentId;
    const selected=arsenal.inventory.get(selectedId),stats=arsenal.stats(selectedId),current=arsenal.stats(),equipped=selectedId===arsenal.currentId,rarity=rarityFor(stats);
    const slots=[...arsenal.inventory.values()].map(entry=>{const item=arsenal.stats(entry.id),color=rarityFor(item),active=entry.id===arsenal.currentId;return `<button class="inventory-slot ${entry.id===selectedId?'selected':''}" data-action="inspect" data-id="${escapeHTML(entry.id)}" aria-pressed="${entry.id===selectedId}" style="--weapon-color:${color.color}"><span>${color.symbol} ${color.name.toUpperCase()} ${entry.favorite?'★':''}</span><strong>${escapeHTML(item.name)}</strong><small>${escapeHTML(item.category)} · ${Math.round(item.damage)} DANO · T${entry.roll?.tier||0}</small><em>${active?'EM USO':`${entry.magazine} / ${entry.reserve}`}</em></button>`;}).join('');
    return `<div class="shop-section-title"><div><span>SUA MOCHILA</span><h3>Cada peça conta.</h3></div><small>${arsenal.inventory.size} / ${INVENTORY_LIMIT} armas · Favoritas protegidas da reciclagem</small></div><div class="inventory-layout"><div class="inventory-slots">${slots}</div><article class="inventory-detail weapon-card" style="--weapon-color:${rarity.color}">${info(stats)}<p>${escapeHTML(stats.description||'')}</p>${equipped?'<p class="equipped-label">EQUIPADA · SUA REFERÊNCIA ATUAL</p>':comparisonHTML(current,stats)}${partsList(selected)}<div class="inventory-actions">${button('equip',selectedId,null,{max:equipped,label:equipped?'EQUIPADA':'EQUIPAR'})}${button('favorite',selectedId,null,{label:selected.favorite?'★ FAVORITA':'☆ MARCAR FAVORITA'})}${button('salvage',selectedId,null,{locked:equipped||selected.favorite||arsenal.salvageValue(selectedId)<=0,label:`RECICLAR · +${money(arsenal.salvageValue(selectedId))} PETISCOS`,title:equipped?'Equipe outra arma antes de reciclar.':selected.favorite?'Desmarque como favorita para reciclar.':'A arma e suas peças viram petiscos.'})}</div></article></div>`;
  }
  function attachmentSummary(part){
    const pieces=[];
    if(part.element)pieces.push(`${ELEMENTS[part.element]?.name||part.element}: altera o comportamento dos tiros`);
    if(part.alternatingElements)pieces.push('Alterna fogo, choque e gelo a cada disparo');
    if(part.burstCount)pieces.push(`Rajada de ${part.burstCount} tiros; cada tiro usa munição`);
    if(part.pierce)pieces.push(`Perfura até ${part.pierce} alvos`);
    if(part.silenced)pieces.push('Assinatura sonora abafada');
    if(part.zoom)pieces.push(`Ampliação de mira ${part.zoom}×`);
    return pieces.join(' · ')||'Ajuste fino de desempenho; compare as mudanças abaixo.';
  }
  function attachments(){
    const current=arsenal.stats(),entry=arsenal.current,fitted=entry.roll?.attachments||{},used=Object.keys(fitted).length,available=current.attachmentSlots||rarityFor(current).slots;
    const owned=[...(arsenal.attachmentStash?.values?.()||[])];
    const stash=owned.length?`<div class="shop-section-title"><div><span>PEÇAS ENCONTRADAS</span><h3>Prontas para instalar.</h3></div></div><div class="training-grid">${owned.map(part=>{const config=ATTACHMENTS[part.attachmentId],preview=arsenal.previewAttachment(config.slot,config.id,part.manufacturer),blocked=!fitted[config.slot]&&used>=available;return `<article class="training-card"><small>${escapeHTML(SLOT_NAMES[config.slot])} · ${escapeHTML(MANUFACTURERS[part.manufacturer]?.name||'')}</small><h3>${escapeHTML(config.name)}</h3><p>${attachmentSummary(config)}</p>${preview?comparisonHTML(current,preview,{compact:true}):''}${attachmentChanges(current,preview)}${button('stash-part',part.id,null,{locked:blocked,label:blocked?'LIMITE DE PEÇAS':'INSTALAR PEÇA GUARDADA'})}${arsenal.salvageAttachmentValue?button('salvage-part',part.id,null,{label:`RECICLAR · +${money(arsenal.salvageAttachmentValue(part.id))} PETISCOS`}):''}</article>`;}).join('')}</div>`:'';
    const cards=Object.values(ATTACHMENTS).filter(part=>part.slot===partSlot).map(part=>{
      const preview=arsenal.previewAttachment(part.slot,part.id,manufacturer),blocked=!fitted[part.slot]&&used>=available,installed=fitted[part.slot]?.id===part.id&&fitted[part.slot]?.manufacturer===manufacturer;
      return `<article class="training-card attachment-card"><span class="part-slot">${escapeHTML(SLOT_NAMES[part.slot])}</span><h3>${escapeHTML(part.name)}</h3><p>${attachmentSummary(part)}</p>${preview?comparisonHTML(current,preview,{compact:true}):''}${attachmentChanges(current,preview)}${button('attachment',part.id,arsenal.attachmentCost(part.id),{locked:blocked||installed,label:installed?'JÁ INSTALADA':blocked?'TROQUE UMA PEÇA EXISTENTE':''})}</article>`;
    }).join('');
    return `<div class="shop-section-title"><div><span>${escapeHTML(current.name)}</span><h3>Monte sua assinatura.</h3></div><small>${used} / ${available} slots · Peças removidas voltam à bolsa</small></div>${partsList(entry,true)}${stash}<div class="part-controls"><label>Peça<select data-control="slot">${Object.entries(SLOT_NAMES).map(([id,label])=>`<option value="${id}" ${partSlot===id?'selected':''}>${label}</option>`).join('')}</select></label><label>Fabricante da peça<select data-control="manufacturer">${Object.values(MANUFACTURERS).map(m=>`<option value="${m.id}" ${manufacturer===m.id?'selected':''}>${escapeHTML(m.name)}</option>`).join('')}</select></label></div><p class="manufacturer-note">${escapeHTML(MANUFACTURERS[manufacturer]?.description)}</p><div class="training-grid">${cards}</div>`;
  }
  function attachmentChanges(current,next){
    if(!next)return '';
    const degrees=value=>`${Number((value*180/Math.PI).toFixed(3))}°`;
    const fields=[['range','Alcance',value=>`${fixed(value)} m`],['recoil','Recuo',degrees],['spread','Dispersão livre',degrees],['aimSpread','Dispersão na mira',degrees],['handling','Controle',fixed],['zoom','Ampliação',value=>`${fixed(value)}×`],['burstCount','Tiros por rajada',fixed],['moveSpeed','Movimento',value=>`${fixed(value*100)}%`]];
    const rows=fields.filter(([key])=>Number.isFinite(current[key])&&Number.isFinite(next[key])&&Math.abs(current[key]-next[key])>1e-7).map(([key,label,format])=>statLine(label,format(current[key]),format(next[key]))).join('');
    return rows?`<div class="attachment-changes"><small>EFEITO DA PEÇA</small>${rows}</div>`:'';
  }
  function forge(){
    if(requireStation&&station!=='forge')return `<div class="station-required"><span class="station-emblem" aria-hidden="true">⌁</span><small>FORJA DE ARMAS</small><h3>Todo grande estrago começa numa oficina.</h3><p>Encontre a estação de forja no mapa e interaja com ela para melhorar tiers ou refazer atributos. A forja aparece com o símbolo ⌁ no mapa.</p><button class="supply-button" data-action="tab" data-id="inventory">Revisar meu equipamento</button></div>`;
    const stats=arsenal.stats(),tier=arsenal.current.roll?.tier||0,cost=arsenal.forgeCost(),next=arsenal.previewForge(),perk=LEGENDARY_PERKS[stats.perk];
    const options=[['stat','Atributos','Refaz um atributo aleatório do roll. Pode melhorar ou piorar. Raridade, modelo e tier são preservados.'],['attachment','Peça','Troca uma peça instalada por uma nova combinação de peça e fabricante.'],['element','Elemento',`Atual: ${elementsFor(stats)}. Sorteia um novo elemento para a arma.`],['perk','Traço lendário',`Atual: ${perk?.name||'Nenhum'}. Lendárias, míticas ou qualquer arma na Forja V.`]];
    return `<div class="shop-section-title"><div><span>FORJA ATIVA · ${escapeHTML(stats.name)}</span><h3>Mais do que números.</h3></div><span class="forge-tier">TIER ${tier} / ${FORGE_MAX_TIER}</span></div><article class="forge-upgrade"><div><p>Tiers aumentam potência e refinam a arma sem apagar sua identidade ou suas peças.</p><div class="forge-steps">${Array.from({length:FORGE_MAX_TIER},(_,i)=>`<span class="${i<tier?'filled':''}">${i+1}</span>`).join('')}</div>${next?comparisonHTML(stats,next):'<p>Esta arma chegou ao tier máximo.</p>'}</div>${button('forge','',cost,{max:cost===null||tier>=FORGE_MAX_TIER,label:cost!==null&&tier<FORGE_MAX_TIER?`TIER ${tier} → ${tier+1} · ◈ ${money(cost)}`:'TIER MÁXIMO'})}</article>${tier>=FORGE_MAX_TIER?refinement(stats):''}<div class="shop-section-title"><div><span>RISCO × RECOMPENSA</span><h3>Refaça a combinação.</h3></div><small>Os custos sobem a cada reroll desta arma.</small></div><div class="training-grid">${options.map(([id,label,description])=>{const value=arsenal.rerollCost(id),locked=value===null||id==='perk'&&!['legendary','mythic'].includes(stats.rarity)&&tier<5;return `<article class="training-card"><h3>Reroll · ${label}</h3><p>${escapeHTML(description)}</p>${button('reroll',id,value,{locked,label:locked?'INDISPONÍVEL':`REFORJAR · ◈ ${money(value)}`})}</article>`;}).join('')}</div>`;
  }
  function refinement(stats){
    const level=arsenal.current.roll.refinement||0,cost=arsenal.refineCost?.(),next=arsenal.previewRefine?.();
    if(cost==null||!next)return '';
    return `<article class="forge-refinement"><div><small>APERFEIÇOAMENTO CONTÍNUO · NÍVEL ${level}</small><h3>Sempre um próximo passo.</h3><p>Potência crescente, sem nível final. Cada aperfeiçoamento também repõe o pente e a reserva desta arma.</p>${statLine('Aperfeiçoamento',level,level+1)}${comparisonHTML(stats,next,{compact:true})}</div>${button('refine','',cost,{label:`APERFEIÇOAR · ◈ ${money(cost)}`})}</article>`;
  }
  function dogs(){
    const training=dog.training,current=training.stats();
    const fields={bite:['Dano','damage',''],tempo:['Tempo entre ataques','attackCooldown','s'],agility:['Velocidade','speed',' m/s'],guard:['Vida','health',' HP'],instinct:['Crítico','criticalChance','%'],pack:['Alvos por ataque','targets',''],element:['Poder especial','element','']};
    const stages=['Mordida','Choque + stun','Choque + lentidão','Execução + onda'];
    const combatCards=Object.entries(DOG_UPGRADES).map(([id,config])=>{
      const next=training.next(id),cost=training.cost(id),unlock=training.unlock(id),locked=roundState.round<unlock,[label,key,suffix]=fields[id];
      const display=value=>id==='element'?stages[value]:id==='instinct'?Math.round(value*100)+suffix:fixed(value)+suffix;
      return `<article class="training-card"><h3>${escapeHTML(config.name)}<small>${training.levels[id]} / ${config.max}</small></h3><p>${escapeHTML(config.description)}</p>${statLine(label,display(current[key]),next?display(next[key]):'MAX')}${id==='guard'&&next?statLine('Resistência',Math.round(current.resistance*100)+'%',Math.round(next.resistance*100)+'%'):''}${button('dog',id,cost,{max:cost===null,locked,label:locked?`ROUND ${unlock}`:''})}</article>`;
    }).join('');
    const talents=Object.values(DOG_TALENTS||{}),talentStats=training.talentStats?.();
    const branches=['support','survival'].map(branch=>{
      const cards=talents.filter(t=>t.branch===branch||t.branch===(branch==='support'?'Support':'Survival')).map(config=>{const id=config.id||Object.keys(DOG_TALENTS).find(key=>DOG_TALENTS[key]===config),next=training.talentNext(id),cost=training.talentCost(id),unlock=training.talentUnlock(id),display=value=>`${fixed(value*(config.unit==='%'?100:1))} ${config.unit||''}`;return `<article class="training-card"><h3>${escapeHTML(config.name)}<small>${training.talents[id]} / ${config.max}</small></h3><p>${escapeHTML(config.description)}</p>${statLine(config.label||'Efeito',display(talentStats[config.stat]),next?display(next[config.stat]):'MAX')}${button('dog-talent',id,cost,{max:cost===null,locked:roundState.round<unlock,label:roundState.round<unlock?`ROUND ${unlock}`:''})}</article>`;}).join('');
      return cards?`<div class="shop-section-title"><div><span>ÁRVORE DO FARO</span><h3>${branch==='support'?'Suporte · Buscar e marcar.':'Sobrevivência · Um cuida do outro.'}</h3></div></div><div class="training-grid">${cards}</div>`:'';
    }).join('');
    return `<div class="dog-shop-intro"><span class="dog-shop-emblem">🐾</span><div><span>SEU PARCEIRO · NÍVEL ${current.level}</span><h3>Faro cresce com você.</h3><p><kbd>C</kbd> alterna caçar / seguir. Equipamento e aparência evoluem com sua árvore.</p></div><button class="supply-button" data-action="dog-heal">Cuidar do Faro · ◈ 40</button></div><div class="shop-section-title"><div><span>ÁRVORE DO FARO</span><h3>Combate · Um parceiro à altura.</h3></div></div><div class="training-grid">${combatCards}</div>${branches}`;
  }
  function player(){
    const director=getDirector(),perks=director?.getPerkOffers?.()||[];
    const perkCards=perks.map(perk=>`<article class="training-card"><small>PERK DE PARTIDA</small><h3>${escapeHTML(perk.name)}</h3><p>${escapeHTML(perk.description)}</p>${perk.before!==undefined?statLine(perk.label||'Efeito',perk.before,perk.after):''}${button('perk',perk.id,perk.price??perk.cost??0,{max:Boolean(perk.maxed),locked:Boolean(perk.locked)})}</article>`).join('');
    return `<div class="shop-section-title"><div><span>O HERÓI DO MORRO</span><h3>Mais fôlego para o caos.</h3></div></div><div class="training-grid">${perkCards}${legacyUpgrades.filter(u=>playerIds.includes(u.id)).map(u=>{const level=state.upgrades[u.id]||0,cost=Math.round(u.base*Math.pow(1.52,level)),[label,before]=comparisons[u.id](level),[,after]=comparisons[u.id](level+1);return `<article class="training-card"><h3>${escapeHTML(u.title)}<small>${level} / 5</small></h3><p>${escapeHTML(u.desc)}</p>${statLine(label,before,level<5?after:'MAX')}${button('player',u.id,cost,{max:level>=5})}</article>`;}).join('')}</div>`;
  }
  function render(){
    if(!root)return;
    const scroll=root.parentElement?.scrollTop||0,coins=document.getElementById('drawerCoins');if(coins)coins.textContent=money(state.coins);root.classList.add('progression-shop');
    const tabs=[['weapons','ARSENAL'],['inventory','INVENTÁRIO'],['attachments','PEÇAS'],['dog','FARO'],['player','MEYUI'],['forge','⌁ FORJA']];
    root.innerHTML=`<nav class="shop-tabs" aria-label="Categorias de melhorias">${tabs.map(([id,label])=>`<button data-action="tab" data-id="${id}" aria-pressed="${tab===id}">${label}${id==='forge'&&station==='forge'?'<i class="station-dot" aria-label="Estação disponível"></i>':''}</button>`).join('')}</nav><section class="shop-content">${({weapons,inventory,attachments,dog:dogs,player,forge})[tab]()}</section>`;
    if(root.parentElement)root.parentElement.scrollTop=scroll;
  }
  function click(event){
    const target=event.target.closest('button[data-action]');if(!target||target.disabled||!root.contains(target))return;
    const {action,id}=target.dataset;
    if(action==='tab'){openTab(id);return;}if(action==='inspect'){selectedId=id;render();return;}
    let success=false;
    if(action==='weapon')success=arsenal.buy(id,state,roundState.round);
    if(action==='equip')success=arsenal.equip(id);
    if(action==='ammo')success=arsenal.refill(state,roundState.round);
    if(action==='weapon-upgrade')success=arsenal.upgrade(id,state);
    if(action==='favorite'&&arsenal.inventory.has(id)){arsenal.toggleFavorite(id);success=true;}
    if(action==='salvage'){const result=arsenal.salvage(id,state);success=result!==false;if(success)toast(`Equipamento reciclado · +${result} petiscos`);}
    if(action==='attachment'){const part=ATTACHMENTS[id];if(part)success=arsenal.installAttachment(part.slot,id,state,manufacturer);}
    if(action==='stash-part')success=arsenal.equipAttachment(id);
    if(action==='remove-part')success=arsenal.removeAttachment(id);
    if(action==='salvage-part'){const result=arsenal.salvageAttachment?.(id,state);success=result!==undefined&&result!==false;if(success)toast(`Peça reciclada · +${result} petiscos`);}
    if(action==='forge'&&(!requireStation||station==='forge'))success=arsenal.forge(state);
    if(action==='refine'&&(!requireStation||station==='forge'))success=arsenal.refine(state);
    if(action==='reroll'&&(!requireStation||station==='forge'))success=arsenal.reroll(id,state);
    if(action==='dog')success=dog.upgrade(id,state,roundState.round);
    if(action==='dog-talent')success=dog.upgradeTalent(id,state,roundState.round);
    if(action==='dog-heal')success=dog.heal(state);
    if(action==='perk')success=getDirector()?.buyPerk?.(id,state)||false;
    if(action==='player'&&playerIds.includes(id)&&state.upgrades[id]<5){const old=state.upgrades[id];buyLegacy(id);success=state.upgrades[id]>old;}
    if(success){
      if(action==='weapon')toast(`${arsenal.stats().name} equipada. Bora testar.`);
      if(action==='refine')toast(`ARMA APERFEIÇOADA · NÍVEL ${arsenal.current.roll.refinement}`);
      if(action==='forge')toast(`ARMA MELHORADA · TIER ${arsenal.current.roll.tier}`);
      if(action==='reroll')toast('Nova combinação pronta. Confira os atributos antes de sair.');
      if(action==='attachment'||action==='stash-part')toast('Peça instalada. A mudança já está valendo.');
      updateUI();render();const focus=[...root.querySelectorAll('button[data-action]')].find(button=>button.dataset.action===action&&button.dataset.id===id);focus?.focus({preventScroll:true});
    }else if(action==='ammo')toast(arsenal.current.reserve>=arsenal.stats().maxReserve?'Sua reserva já está cheia.':'Faltam petiscos para repor munição.');
    else if(action==='dog-heal')toast('Faro está bem ou faltam petiscos.');
    else if(!['equip','favorite'].includes(action))toast('Esta melhoria não está disponível agora. Confira petiscos, slots e requisitos.');
  }
  function change(event){if(event.target.dataset.control==='slot')partSlot=event.target.value;if(event.target.dataset.control==='manufacturer')manufacturer=event.target.value;render();}
  function openTab(id){const aliases={arsenal:'weapons',parts:'attachments',meyui:'player',faro:'dog'};const next=aliases[id]||id;if(!['weapons','inventory','attachments','dog','player','forge'].includes(next))return false;tab=next;render();return true;}
  root?.addEventListener('click',click);root?.addEventListener('change',change);
  return {render,openTab,setStation(kind){station=kind||null;},getStation:()=>station,getTab:()=>tab,dispose(){root?.removeEventListener('click',click);root?.removeEventListener('change',change);}};
}
