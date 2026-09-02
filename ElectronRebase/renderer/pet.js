(function initPaimonPet() {
  const stage = document.getElementById('pet-stage');
  const sprite = document.getElementById('pet-sprite');
  if (!stage || !sprite || !window.paimonPetAPI) return;

  const FRAME_COUNT = 16;
  const FRAME_MS = 110;
  let frame = 0;
  let frameTimer = null;
  let animation = 'idle';
  let pointer = null;
  let dragging = false;

  function drawFrame() {
    const x = frame % 4;
    const y = Math.floor(frame / 4);
    sprite.style.backgroundPosition = `${(x / 3) * 100}% ${(y / 3) * 100}%`;
  }

  function play(next, once = false) {
    animation = next;
    frame = 0;
    sprite.className = `pet-sprite is-${next}`;
    drawFrame();
    if (frameTimer) clearInterval(frameTimer);
    frameTimer = setInterval(() => {
      frame += 1;
      if (frame >= FRAME_COUNT) {
        if (once) {
          play('idle');
          return;
        }
        frame = 0;
      }
      drawFrame();
    }, FRAME_MS);
  }

  stage.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    stage.setPointerCapture(event.pointerId);
    pointer = {
      id: event.pointerId,
      startX: event.screenX,
      startY: event.screenY,
      lastX: event.screenX,
      lastY: event.screenY,
    };
    dragging = false;
  });

  stage.addEventListener('pointermove', (event) => {
    if (!pointer || pointer.id !== event.pointerId) return;
    const distance = Math.hypot(event.screenX - pointer.startX, event.screenY - pointer.startY);
    if (!dragging && distance >= 5) {
      dragging = true;
      document.body.classList.add('is-dragging');
      window.paimonPetAPI.beginDrag(pointer.startX, pointer.startY);
    }
    if (!dragging) return;
    pointer.lastX = event.screenX;
    pointer.lastY = event.screenY;
    window.paimonPetAPI.dragTo(event.screenX, event.screenY);
  });

  function finishPointer(event) {
    if (!pointer || pointer.id !== event.pointerId) return;
    const wasDragging = dragging;
    pointer = null;
    dragging = false;
    document.body.classList.remove('is-dragging');
    if (wasDragging) {
      window.paimonPetAPI.endDrag();
    } else {
      play('clicking', true);
      window.paimonPetAPI.openAssistant();
    }
  }

  stage.addEventListener('pointerup', finishPointer);
  stage.addEventListener('pointercancel', finishPointer);

  window.paimonPetAPI.onMode((payload) => {
    const mode = payload && payload.mode || 'idle';
    stage.classList.toggle('is-docked', payload && payload.docked === true);
    if (mode === 'docking') {
      stage.classList.add('is-docking');
      return;
    }
    stage.classList.remove('is-docking');
    play(['idle', 'listening', 'speaking', 'clicking'].includes(mode) ? mode : 'idle');
  });

  play(animation);
})();
