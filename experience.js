// Interaction and presentation are kept separate from world generation.
export function normalizeSettings(value = {}) {
  const number = (key, fallback, min, max) => Number.isFinite(value[key]) ? Math.min(max, Math.max(min, value[key])) : fallback;
  return {
    sensitivity: number('sensitivity', 1, .3, 2.5),
    volume: number('volume', 50, 0, 100),
    musicVolume: number('musicVolume', 35, 0, 100),
    effectsVolume: number('effectsVolume', 80, 0, 100),
    cameraDistance: number('cameraDistance', 6.5, 4, 10),
    invertY: value.invertY === true,
    reduceMotion: value.reduceMotion === true,
  };
}

export function createExperience(game) {
  const { THREE, state, player, ui, keys, upgrades, scene, camera, renderer, dog, dogParts, barkView,
    roundState, solidColliders, objects, chaosBots, colossi, projectiles, bark, sniff, dig, jump, dash,
    formPack, renderUpgrades, renderMissions, drawMiniMap, updateUI, initAudio, startMusic, playSound,
    dust, showToast, getBoss, setShake, setVolume, pauseMusic, resumeMusic } = game;
  const $ = id => document.getElementById(id);
  const shell = document.querySelector('.game-shell');
  const canvas = $('game');
  const modalIds = ['pauseScreen', 'settingsScreen', 'helpScreen', 'upgradeDrawer', 'missionDrawer', 'mapDrawer', 'gameOverScreen'];
  const iconIds = {speed:'bolt',jump:'up',dash:'bolt',force:'wave',ammo:'spark',range:'target',crit:'target',bark:'wave',armor:'shield',regen:'heart',magnet:'bone',luck:'spark',dig:'paw',secret:'compass',pack:'paw',pupPower:'wave',elemental:'spark'};
  const groupColors = {'MOVIMENTO':'#e2bf77','COMBATE':'#e39c86','DEFESA':'#9dcabc','EXPLORAÇÃO':'#a5bdda','GANGUE':'#c4a6d9'};
  const purchased = new Set();
  const cameraPosition = new THREE.Vector3();
  const aimDirection = new THREE.Vector3();
  let settings = normalizeSettings({ reduceMotion: matchMedia('(prefers-reduced-motion: reduce)').matches });
  try { const saved = JSON.parse(localStorage.getItem('meyui-settings') || 'null'); if (saved && typeof saved === 'object') settings = normalizeSettings(saved); } catch { /* Private browsing can disable storage. */ }
  let currentModal = null, modalReturn = null, previousFocus = null;
  let shootHeld = false, touchLook = null, pointerMode = 'pending', lockPending = false, unlockAt = -Infinity;
  let hasStarted = false, ended = false, cameraReady = false, aimBlend = 0, displayedCoins = state.coins;
  let totalEarned = 0, announcementTime = 0, feedbackTime = 0, scoreTime = 0, hudTime = 0, lastPerkSignature = '';
  let lastPointer = null, pointerNotice = false, menuTime = 0, escapeRelease = false;

  function icon(id) { return `<svg aria-hidden="true"><use href="#icon-${iconIds[id] || id}"/></svg>`; }
  function resetInput() {
    Object.keys(keys).forEach(key => keys[key] = 0);
    shootHeld = false; touchLook = null; lastPointer = null;
    player.aiming = player.aimHeld = false;
    player.moveVelocity.set(0, 0, 0);
    shell.classList.remove('aiming', 'firing', 'target-enemy');
    $('joystick').querySelector('i').style.transform = '';
  }
  function releaseMouse() {
    resetInput();
    if (document.pointerLockElement === canvas) document.exitPointerLock();
  }
  function lockFallback(error) {
    lockPending = false;
    if (!state.running || state.paused) return;
    pointerMode = 'free';
    canvas.dataset.mouseMode = 'free';
    if (error?.name) console.info('Mouse capture unavailable:', error.name, error.message);
    if (!pointerNotice) { showToast('Mova o mouse para olhar. P pausa; tela cheia amplia a área de movimento.'); pointerNotice = true; }
  }
  function requestMouse() {
    if (matchMedia('(pointer:coarse)').matches || document.pointerLockElement === canvas || pointerMode === 'free' || lockPending) return;
    if (!canvas.requestPointerLock) { lockFallback(); return; }
    // Escape imposes a browser cooldown. Keep the game paused until another click.
    if (performance.now() - unlockAt < 1200) {
      pause('Mouse liberado. Clique em CONTINUAR para voltar quando estiver pronto.');
      return;
    }
    lockPending = true;
    try { const pending = canvas.requestPointerLock(); pending?.catch(lockFallback); } catch { lockFallback(); }
  }
  function focusModal(id) {
    const focusable = $(id).querySelector('button:not(:disabled),input');
    focusable?.focus({ preventScroll: true });
  }
  function showModal(id, returnTo = null) {
    if (ended && id !== 'gameOverScreen') return;
    previousFocus = document.activeElement;
    modalReturn = returnTo;
    modalIds.forEach(name => $(name).hidden = name !== id);
    currentModal = id;
    state.paused = true;
    displayedCoins = state.coins;
    ui.coins.textContent = state.coins.toLocaleString('pt-BR');
    shell.classList.add('modal-open');
    shell.classList.remove('playing');
    $('gameHud').inert = true;
    $('startScreen').inert = true;
    releaseMouse(); pauseMusic();
    if (id === 'upgradeDrawer') renderUpgrades();
    if (id === 'missionDrawer') renderMissions();
    if (id === 'mapDrawer') { updateUI(); drawMiniMap(); }
    if (id === 'pauseScreen') {
      $('pauseRound').textContent = String(roundState.round).padStart(2, '0');
      $('pauseCoins').textContent = state.coins.toLocaleString('pt-BR');
    }
    focusModal(id);
  }
  function closeModal() {
    if (ended) return;
    if (modalReturn) { const target = modalReturn; modalReturn = null; showModal(target); return; }
    if (hasStarted && ui.startScreen.hidden) { resume(); return; }
    modalIds.forEach(id => $(id).hidden = true);
    currentModal = null;
    shell.classList.remove('modal-open');
    $('startScreen').inert = false;
    previousFocus?.focus?.({ preventScroll: true });
  }
  function pause(message) {
    if (!hasStarted || ended || !ui.startScreen.hidden) return;
    showModal('pauseScreen');
    $('pauseFoot').textContent = message || 'O jogo fica pausado enquanto você estiver aqui.';
  }
  function resume() {
    if (ended) return;
    modalIds.forEach(id => $(id).hidden = true);
    ui.startScreen.hidden = true;
    ui.startScreen.inert = false;
    $('gameHud').hidden = false;
    $('gameHud').inert = false;
    currentModal = modalReturn = null;
    state.running = true; state.paused = false;
    shell.classList.remove('menu-open', 'modal-open');
    shell.classList.add('playing');
    resetInput(); canvas.focus({ preventScroll: true });
    initAudio(); resumeMusic(); requestMouse();
  }
  function start() {
    if (!hasStarted) {
      hasStarted = true; cameraReady = false;
      player.cameraYaw = 0; player.cameraPitch = -.045;
      player.damageCooldown = 3;
      startMusic();
      announce('BEM-VINDO AO CALÇADÃO', 'SIGA SEU FARO', 'Pegue petiscos. Prepare-se para o primeiro round.');
    }
    resume();
  }
  function mainMenu() {
    releaseMouse(); state.paused = true;
    modalIds.forEach(id => $(id).hidden = true);
    currentModal = modalReturn = null;
    ui.startScreen.hidden = false; ui.startScreen.inert = false;
    $('gameHud').hidden = true;
    shell.classList.remove('playing', 'modal-open'); shell.classList.add('menu-open');
    $('startButtonLabel').textContent = 'CONTINUAR AVENTURA';
    $('startButton').focus(); pauseMusic();
  }
  function openDrawer(id) { if (!hasStarted || ended) return; showModal(id); }
  function rotate(dx, dy) {
    const sensitivity = .0025 * settings.sensitivity * (player.aiming ? .62 : 1);
    player.cameraYaw -= Math.max(-200, Math.min(200, dx)) * sensitivity;
    player.cameraPitch = THREE.MathUtils.clamp(player.cameraPitch - dy * sensitivity * (settings.invertY ? -1 : 1), -1.1, 1.05);
  }
  function updateSettings(save = false) {
    for (const key of ['sensitivity','volume','musicVolume','effectsVolume','cameraDistance']) {
      $(key).value = settings[key];
      $(key + 'Value').textContent = key.toLowerCase().includes('volume') ? `${settings[key]}%` : settings[key].toFixed(1);
    }
    $('invertY').checked = settings.invertY;
    $('reduceMotion').checked = settings.reduceMotion;
    shell.classList.toggle('reduce-motion', settings.reduceMotion);
    setVolume(settings.volume / 100);
    game.setAudioMix?.(settings.musicVolume/100,settings.effectsVolume/100);
    if (save) try { localStorage.setItem('meyui-settings', JSON.stringify(settings)); } catch { /* Storage is optional. */ }
  }
  function bind() {
    updateSettings();
    $('startButton').onclick = start;
    $('resumeButton').onclick = resume;
    $('pauseButton').onclick = () => pause();
    $('mainMenuButton').onclick = mainMenu;
    $('restartButton').onclick = () => location.reload();
    $('gameOverMenuButton').onclick = () => location.reload();
    $('startHelpButton').onclick = () => showModal('helpScreen');
    $('startSettingsButton').onclick = () => showModal('settingsScreen');
    $('pauseHelpButton').onclick = () => showModal('helpScreen', 'pauseScreen');
    $('pauseSettingsButton').onclick = () => showModal('settingsScreen', 'pauseScreen');
    $('pauseUpgradeButton').onclick = () => showModal('upgradeDrawer', 'pauseScreen');
    $('upgradeButton').onclick = () => openDrawer('upgradeDrawer');
    $('mapButton').onclick = () => openDrawer('mapDrawer');
    $('missionButton').onclick = () => showModal('missionDrawer', 'mapDrawer');
    $('sniffButton').onclick = sniff; $('barkButton').onclick = bark; $('dashButton').onclick = dash;
    $('mobileReload').onclick = () => game.getCombat()?.reload();
    $('reloadButton').onclick = () => game.getCombat()?.reload();
    $('mobileSwap').onclick = () => game.getCombat()?.arsenal.cycle(1);
    canvas.addEventListener('wheel', e => {if(state.running&&!state.paused){e.preventDefault();game.getCombat()?.arsenal.cycle(Math.sign(e.deltaY));}},{passive:false});
    $('mobileJump').onclick = jump; $('mobileBark').onclick = bark;
    $('mobileAim').onclick = () => { if (!state.paused) player.aiming = player.aimHeld = !player.aiming; };
    $('mobileFire').addEventListener('pointerdown', e => { if (!state.paused) { e.preventDefault(); shootHeld = true; shoot(); $('mobileFire').setPointerCapture(e.pointerId); } });
    $('mobileFire').addEventListener('pointerup', () => shootHeld = false);
    $('mobileFire').addEventListener('pointercancel', () => shootHeld = false);
    $('prestigeButton').onclick = game.prestige;
    document.querySelectorAll('[data-close]').forEach(button => button.onclick = closeModal);
    for (const name of ['sensitivity','volume','musicVolume','effectsVolume','cameraDistance','invertY','reduceMotion']) $(name).addEventListener('input', () => {
      settings[name] = $(name).type === 'checkbox' ? $(name).checked : Number($(name).value);
      updateSettings(true);
    });
    addEventListener('resize', game.resize);
    addEventListener('keydown', e => {
      if (e.code === 'Tab' && currentModal) {
        const nodes = [...$(currentModal).querySelectorAll('button:not(:disabled),input')].filter(node => node.getClientRects().length);
        if (!nodes.length) return;
        if (e.shiftKey && document.activeElement === nodes[0]) { e.preventDefault(); nodes.at(-1).focus(); }
        else if (!e.shiftKey && document.activeElement === nodes.at(-1)) { e.preventDefault(); nodes[0].focus(); }
        return;
      }
      if (e.code === 'Escape' || e.code === 'KeyP') {
        if (e.repeat || ended) return;
        e.preventDefault();
        if (e.code === 'Escape' && document.pointerLockElement === canvas) { escapeRelease = true; pause(); return; }
        if (currentModal) { if (currentModal === 'pauseScreen' && e.code === 'Escape') return; closeModal(); }
        else pause();
        return;
      }
      if (currentModal || !hasStarted || state.paused || ended) return;
      if (['F1','Space','Tab','ArrowUp','ArrowDown','ArrowLeft','ArrowRight'].includes(e.code)) e.preventDefault();
      keys[e.code] = true;
      if (e.repeat) return;
      const actions = { KeyR:()=>game.getCombat()?.reload(), KeyC:()=>game.getDog()?.command(), KeyE:bark, KeyQ:sniff, KeyF:dig, KeyG:formPack, Space:jump, ShiftLeft:dash, ShiftRight:dash,
        F1:()=>{player.thirdPerson=!player.thirdPerson;cameraReady=false;canvas.dataset.perspective=player.thirdPerson?'third':'first';showToast(player.thirdPerson?'Terceira pessoa · F1 para voltar':'Primeira pessoa · F1 para alternar');},
        Tab:() => openDrawer('upgradeDrawer'), KeyU:() => openDrawer('upgradeDrawer'), KeyM:() => openDrawer('mapDrawer'), KeyJ:() => openDrawer('missionDrawer'), KeyH:() => showModal('helpScreen') };
      actions[e.code]?.();
      if(/^Digit[1-7]$/.test(e.code))game.getCombat()?.arsenal.equip(['biscuit','boardwalk','hammer','popcorn','ember','voltage','zero'][Number(e.code.at(-1))-1]);
    });
    addEventListener('keyup', e => keys[e.code] = false);
    canvas.addEventListener('contextmenu', e => e.preventDefault());
    canvas.addEventListener('pointerdown', e => {
      if (!state.running || state.paused) return;
      if (e.pointerType === 'touch') { touchLook = {id:e.pointerId,x:e.clientX,y:e.clientY}; canvas.setPointerCapture(e.pointerId); return; }
    });
    // Mouse events report each button independently. Pointerdown only reports the FIRST
    // pressed button, which previously swallowed left clicks while holding right to aim.
    canvas.addEventListener('mousedown', e => {
      if (!state.running || state.paused || e.sourceCapabilities?.firesTouchEvents) return;
      e.preventDefault(); requestMouse();
      if (e.button === 2) player.aiming = player.aimHeld = true;
      if (e.button === 0) { shootHeld = true; shoot(); }
    });
    canvas.addEventListener('pointermove', e => {
      if (state.paused || !state.running) return;
      if (e.pointerType === 'touch' && touchLook?.id === e.pointerId) {
        rotate((e.clientX-touchLook.x)*1.6, (e.clientY-touchLook.y)*1.6);
        touchLook.x=e.clientX; touchLook.y=e.clientY;
      }
    });
    document.addEventListener('mousemove', e => {
      if (state.paused || !state.running) return;
      if (document.pointerLockElement === canvas) rotate(e.movementX, e.movementY);
      else if (pointerMode === 'free') {
        if (lastPointer) rotate(e.clientX-lastPointer.x, e.clientY-lastPointer.y);
        lastPointer = {x:e.clientX,y:e.clientY};
      }
    });
    addEventListener('pointerup', e => {
      if (e.pointerType === 'touch' && touchLook?.id === e.pointerId) touchLook = null;
    });
    addEventListener('mouseup', e => {
      if (e.button === 0) shootHeld = false;
      if (e.button === 2) player.aiming = player.aimHeld = false;
    });
    addEventListener('pointercancel', resetInput);
    document.addEventListener('pointerlockchange', () => {
      lockPending = false;
      if (document.pointerLockElement === canvas) {
        if (state.paused) { document.exitPointerLock(); return; }
        pointerMode = 'locked'; lastPointer = null;
        canvas.dataset.mouseMode = 'locked';
      } else if (pointerMode === 'locked') {
        pointerMode = 'pending';
        if (!state.paused || escapeRelease) unlockAt = performance.now();
        escapeRelease = false;
        if (!state.paused) pause();
      }
    });
    document.addEventListener('pointerlockerror', lockFallback);
    addEventListener('blur', () => { resetInput(); if (state.running && !state.paused) pause('Você saiu do jogo. A aventura está pausada.'); });
    document.addEventListener('visibilitychange', () => { if (document.hidden && state.running && !state.paused) pause('A aventura foi pausada ao trocar de aba.'); });
    canvas.addEventListener('pointerleave', () => { lastPointer = null; if (pointerMode === 'free' && !state.paused) pause(); });
    const stick = $('joystick'), knob = stick.querySelector('i');
    let stickPointer = null;
    const moveStick = e => {
      if (stickPointer !== e.pointerId || state.paused) return;
      const rect = stick.getBoundingClientRect(), dx=e.clientX-rect.left-rect.width/2, dy=e.clientY-rect.top-rect.height/2;
      const length = Math.hypot(dx,dy) || 1, amount = Math.min(1,length/30);
      keys.touchX=dx/length*amount; keys.touchY=dy/length*amount;
      knob.style.transform=`translate(${keys.touchX*25}px,${keys.touchY*25}px)`;
    };
    stick.addEventListener('pointerdown', e => { if (state.paused) return; stickPointer=e.pointerId; stick.setPointerCapture(e.pointerId); moveStick(e); });
    stick.addEventListener('pointermove', moveStick);
    for (const event of ['pointerup','pointercancel','lostpointercapture']) stick.addEventListener(event, () => { stickPointer=null; keys.touchX=keys.touchY=0; knob.style.transform=''; });
    $('startButton').disabled = false;
    $('startButtonLabel').textContent = 'COMEÇAR A AVENTURA';
    $('loadingStatus').textContent = 'Tudo pronto. Seu calçadão está esperando.';
    renderPerks();
  }

  function trace(origin, direction, range, enemies = true, padding = 0) {
    const world=game.getCombat()?.hitWorld;
    return world ? (enemies ? world.cast(origin,direction,range)[0] : world.surfaces(origin,direction,range,{padding})) : null;
  }
  function updateCamera(dt) {
    const blend = 1-Math.exp(-dt*14);
    aimBlend = player.thirdPerson ? 0 : 1;
    const combat=game.getCombat(), pitch=player.cameraPitch+(combat?.recoilPitch||0),yaw=player.cameraYaw+(combat?.recoilYaw||0);
    aimDirection.set(Math.sin(yaw)*Math.cos(pitch),Math.sin(pitch),Math.cos(yaw)*Math.cos(pitch));
    const pivot = player.pos.clone(); pivot.y += 1.3;
    const eye = player.pos.clone().add(new THREE.Vector3(0,1.3,0));
    const behind = pivot.clone().addScaledVector(aimDirection,-settings.cameraDistance);
    // A slight shoulder offset keeps Meyui visible without obstructing the reticle.
    behind.add(new THREE.Vector3(-Math.cos(player.cameraYaw)*1.15,0,Math.sin(player.cameraYaw)*1.15));
    behind.y=Math.max(player.pos.y+.5,behind.y);
    const desired=behind.lerp(eye,aimBlend);
    const segment=desired.clone().sub(pivot), length=segment.length();
    if(length>.01){const obstruction=trace(pivot,segment.normalize(),length,false,.22); if(obstruction) desired.copy(pivot).addScaledVector(segment,Math.max(.12,obstruction.distance-.1));}
    if(!cameraReady){cameraPosition.copy(desired);cameraReady=true;}
    // Position follows softly; look direction follows the mouse immediately.
    if(player.thirdPerson)cameraPosition.lerp(desired,1-Math.exp(-dt*24));else cameraPosition.copy(desired);
    const cameraTravel=cameraPosition.clone().sub(pivot), travelLength=cameraTravel.length();
    if(travelLength>.01){const hit=trace(pivot,cameraTravel.normalize(),travelLength,false,.15);if(hit)cameraPosition.copy(pivot).addScaledVector(cameraTravel,Math.max(.1,hit.distance-.08));}
    camera.position.copy(cameraPosition);
    if(!settings.reduceMotion){const shake=game.getCombat()?.effects.shake||0;camera.position.x+=Math.sin(state.time*97)*shake;camera.position.y+=Math.cos(state.time*83)*shake*.6;}
    camera.lookAt(camera.position.clone().add(aimDirection));
    const fov=THREE.MathUtils.lerp(camera.fov,player.aiming?52:player.dash>0&&!settings.reduceMotion?72:66,blend);
    if(Math.abs(camera.fov-fov)>.001){camera.fov=fov;camera.updateProjectionMatrix();}
    dog.visible=Boolean(player.thirdPerson);
    barkView.visible=false;
    barkView.position.set(0,-.5,-.7+player.firing*.12);

    shell.classList.toggle('aiming',player.aiming);
    shell.classList.toggle('firing',player.firing>.03);
    if(player.aiming) player.dir=player.cameraYaw;
    camera.updateMatrixWorld(true);
    const target=game.getCombat()?.preview();
    shell.classList.toggle('target-enemy',Boolean(target?.hits.some(hit=>['enemy','boss'].includes(hit.kind))));
    shell.classList.toggle('target-blocked',Boolean(target?.blocked));
  }
  function shoot() {
    if(!state.running||state.paused)return false;
    updateCamera(0);
    return game.getCombat()?.fire() || false;
  }
  function resolveShot(shot) { shot.life=0; }
  function reward(value) {
    if(!hasStarted)return;
    if(value>0)totalEarned+=value;
    if(value<0)displayedCoins=state.coins;
    const feed=$('rewardFeed'),label=document.createElement('span');
    label.className=`reward-float${value>=100?' big':''}${value<0?' spent':''}`;
    label.textContent=`${value>0?'+':''}${value.toLocaleString('pt-BR')}`;
    label.style.top=`${feed.childElementCount%4*-20}px`;
    if(feed.childElementCount>=6)feed.firstElementChild.remove();
    feed.append(label);setTimeout(()=>label.remove(),1250);
    shell.classList.remove('score-pop');void feed.offsetWidth;shell.classList.add('score-pop');scoreTime=.35;
  }
  function markPurchased(id) { purchased.add(id);renderPerks(); }
  function clearPurchased() { purchased.clear();renderPerks(); }
  function renderPerks() {
    const items=upgrades.filter(u=>purchased.has(u.id)&&state.upgrades[u.id]>0).map(u=>({...u,level:state.upgrades[u.id],color:groupColors[u.group]}));
    const arsenal=game.getCombat()?.arsenal,training=game.getDog()?.training;
    if(arsenal)for(const [id,level] of Object.entries(arsenal.current.upgrades))if(level)items.push({id:'gun-'+id,title:({damage:'Impacto',magazine:'Pente estendido',reload:'Recarga rápida'})[id],symbol:id==='reload'?'bolt':'target',level,color:arsenal.stats().color});
    if(training)for(const [id,level] of Object.entries(training.levels))if(level)items.push({id:'dog-'+id,title:'Faro · '+({bite:'mordida',tempo:'cadência',agility:'velocidade',guard:'proteção',instinct:'crítico',pack:'matilha',element:'elemental'})[id],symbol:id==='element'?'spark':id==='guard'?'shield':'paw',level,color:'#99cfc0'});
    const signature=items.map(u=>u.id+u.level+u.color).join(',');
    if(signature===lastPerkSignature&&$('powerupSlots').childElementCount)return;
    lastPerkSignature=signature;
    $('powerupLabel').textContent=items.length?'SEUS AU-MENTOS':'SEU INSTINTO É SÓ O COMEÇO';
    $('powerupSlots').innerHTML=items.length?items.slice(0,7).map(u=>`<button class="perk" data-perk="${u.id}" style="--perk-color:${u.color}" aria-label="${u.title}, nível ${u.level}" title="${u.title} · NV ${u.level}">${icon(u.symbol||u.id)}<small>${u.level}</small><span class="perk-tooltip">${u.title}</span></button>`).join('')+(items.length>7?`<button class="perk perk-more" title="Ver todas as melhorias" aria-label="Ver todas as melhorias">+${items.length-7}</button>`:''):'<span class="empty-powerups">Compre melhorias <kbd>TAB</kbd></span>';
    $('powerupSlots').querySelectorAll('button').forEach(button=>button.onclick=()=>openDrawer('upgradeDrawer'));
  }
  function announce(label,title,text) {
    $('roundAnnouncementLabel').textContent=label;$('roundAnnouncementTitle').textContent=title;$('roundAnnouncementText').textContent=text;
    $('roundAnnouncement').classList.add('show');announcementTime=3.2;
  }
  function damage() {shell.classList.add('damaged');feedbackTime=.3;}
  function endGame() {
    ended=true;shootHeld=false;state.paused=true;
    $('resultRound').textContent=String(roundState.round).padStart(2,'0');
    $('resultScore').textContent=totalEarned.toLocaleString('pt-BR');
    $('resultTime').textContent=`${Math.floor(state.time/60)}:${String(Math.floor(state.time%60)).padStart(2,'0')}`;
    showModal('gameOverScreen');
  }
  function tick(dt) {
    if(!hasStarted||!ui.startScreen.hidden){
      menuTime+=dt;dog.visible=true;barkView.visible=false;
      const angle=.85+(settings.reduceMotion?0:Math.sin(menuTime*.13)*.08);
      const distance=innerWidth<700?8.2:6.8;
      camera.position.set(player.pos.x+Math.sin(angle)*distance,player.pos.y+2.65,player.pos.z-Math.cos(angle)*distance);
      camera.fov=45;camera.updateProjectionMatrix();
      camera.lookAt(player.pos.x-1.7,player.pos.y+.7,player.pos.z);
      cameraReady=false;return;
    }
    if(state.paused)return;
    if(shootHeld)shoot();
    displayedCoins=THREE.MathUtils.lerp(displayedCoins,state.coins,1-Math.exp(-dt*14));
    if(Math.abs(displayedCoins-state.coins)<.5)displayedCoins=state.coins;
    ui.coins.textContent=Math.round(displayedCoins).toLocaleString('pt-BR');
    ui.health.textContent=Math.ceil(player.health);ui.healthFill.style.width=`${player.health}%`;
    shell.classList.toggle('low-health',player.health<=30);
    $('healthStatus').textContent=player.health<=30?'PRECISA DE UM PETISCO':player.health<70?'FIRME E FORTE':'PRONTO PRO CAOS';
    $('onboarding').classList.toggle('faded',state.time>18);
    const barkMax=Math.max(.7,2.1-state.upgrades.bark*.12),dashMax=Math.max(.28,1.05-state.upgrades.dash*.085);
    ui.barkCooldown.style.transform=`scaleY(${Math.min(1,(player.barkCooldown||0)/barkMax)})`;
    $('dashCooldown').style.transform=`scaleY(${Math.min(1,player.dashCooldown/dashMax)})`;
    if(announcementTime>0){announcementTime-=dt;if(announcementTime<=0)$('roundAnnouncement').classList.remove('show');}
    if(feedbackTime>0){feedbackTime-=dt;if(feedbackTime<=0)shell.classList.remove('damaged');}
    if(scoreTime>0){scoreTime-=dt;if(scoreTime<=0)shell.classList.remove('score-pop');}
    hudTime+=dt;if(hudTime>.15){hudTime=0;$('healthFill').parentElement.setAttribute('aria-valuenow',Math.ceil(player.health));ui.treats.textContent=state.treats;renderPerks();}
  }
  function portrait() {
    const portraitScene=new THREE.Scene();
    portraitScene.add(new THREE.HemisphereLight('#fff0ce','#374b43',2.4));
    const light=new THREE.DirectionalLight('#ffe0b5',3);light.position.set(-3,5,-4);portraitScene.add(light);
    const clone=dog.clone(true);clone.position.set(0,0,0);clone.rotation.set(0,0,0);clone.visible=true;portraitScene.add(clone);
    const bounds=new THREE.Box3().setFromObject(clone),center=bounds.getCenter(new THREE.Vector3()),size=bounds.getSize(new THREE.Vector3());
    const portraitCamera=new THREE.PerspectiveCamera(34,1,.1,30);
    portraitCamera.position.copy(center).add(new THREE.Vector3(1.1,.5,-1.5).normalize().multiplyScalar(Math.max(size.x,size.y,size.z)*2));
    portraitCamera.lookAt(center);
    // Reuse the existing WebGL context, then release the temporary render target.
    const target=new THREE.WebGLRenderTarget(256,256);target.texture.colorSpace=THREE.SRGBColorSpace;
    const previous=renderer.getRenderTarget(),oldColor=renderer.getClearColor(new THREE.Color()),oldAlpha=renderer.getClearAlpha();
    renderer.setRenderTarget(target);renderer.setClearColor('#263a35',0);renderer.render(portraitScene,portraitCamera);
    const pixels=new Uint8Array(256*256*4);renderer.readRenderTargetPixels(target,0,0,256,256,pixels);
    renderer.setRenderTarget(previous);renderer.setClearColor(oldColor,oldAlpha);target.dispose();
    const output=document.createElement('canvas');output.width=output.height=256;const context=output.getContext('2d'),data=context.createImageData(256,256);
    for(let row=0;row<256;row++)data.data.set(pixels.subarray((255-row)*1024,(256-row)*1024),row*1024);
    context.putImageData(data,0,0);const url=output.toDataURL('image/png');document.querySelectorAll('.meyui-portrait').forEach(img=>img.src=url);
  }
  return {bind,tick,updateCamera,shoot,resolveShot,reward,markPurchased,clearPurchased,renderPerks,announce,damage,endGame,openDrawer,
    closeModal,portrait,icon,settings,trace,pause,resetInput};
}
