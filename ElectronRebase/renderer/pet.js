(function initPaimonPet() {
  const stage = document.getElementById('pet-stage');
  const sprite = document.getElementById('pet-sprite');
  if (!stage || !(sprite instanceof HTMLCanvasElement) || !window.paimonPetAPI) return;

  const FRAME_COUNT = 16;
  const GRID_SIZE = 4;
  const SOURCE_FRAME_SIZE = 314;
  const DISPLAY_SIZE = 216;
  const IDLE_FRAME_MS = 110;
  const ACTIVE_FRAME_MS = 110;
  const IDLE_REST_MS = 5200;
  const sheets = {
    idle: 'assets/paimon/idle.png',
    listening: 'assets/paimon/listening.png',
    speaking: 'assets/paimon/speaking.png',
    clicking: 'assets/paimon/click.png',
  };
  const frameCaches = new Map();
  const pixelRatio = Math.min(3, Math.max(1, window.devicePixelRatio || 1));
  const outputSize = Math.round(DISPLAY_SIZE * pixelRatio);
  const context = sprite.getContext('2d', { alpha: true, desynchronized: false });
  sprite.width = outputSize;
  sprite.height = outputSize;
  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = 'high';

  let frame = 0;
  let frameTimer = null;
  let playGeneration = 0;
  let animation = 'idle';
  let pointer = null;
  let dragging = false;
  let docked = false;

  function loadSheet(source) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = reject;
      image.src = source;
    });
  }

  async function framesFor(mode) {
    if (frameCaches.has(mode)) return frameCaches.get(mode);
    const loading = loadSheet(sheets[mode]).then((image) => {
      const frames = [];
      for (let index = 0; index < FRAME_COUNT; index += 1) {
        const canvas = document.createElement('canvas');
        canvas.width = outputSize;
        canvas.height = outputSize;
        const frameContext = canvas.getContext('2d', { alpha: true });
        frameContext.imageSmoothingEnabled = true;
        frameContext.imageSmoothingQuality = 'high';
        frameContext.drawImage(
          image,
          (index % GRID_SIZE) * SOURCE_FRAME_SIZE,
          Math.floor(index / GRID_SIZE) * SOURCE_FRAME_SIZE,
          SOURCE_FRAME_SIZE,
          SOURCE_FRAME_SIZE,
          0,
          0,
          outputSize,
          outputSize
        );
        frames.push(canvas);
      }
      return frames;
    });
    frameCaches.set(mode, loading);
    return loading;
  }

  function drawFrame(frames) {
    context.clearRect(0, 0, outputSize, outputSize);
    context.drawImage(frames[frame], 0, 0);
    stage.classList.add('is-ready');
  }

  async function play(next, options = {}) {
    const generation = ++playGeneration;
    animation = next;
    frame = 0;
    sprite.className = `pet-sprite is-${next}`;
    if (frameTimer) clearTimeout(frameTimer);
    let frames;
    try {
      frames = await framesFor(next);
    } catch (error) {
      return;
    }
    if (generation !== playGeneration) return;
    drawFrame(frames);

    const once = options.once === true;
    const startWithRest = options.startWithRest === true;
    const frameDelay = next === 'idle' ? IDLE_FRAME_MS : ACTIVE_FRAME_MS;
    const advance = () => {
      if (generation !== playGeneration) return;
      frame += 1;
      if (frame >= FRAME_COUNT) {
        if (once) {
          void play('idle', { startWithRest: true });
          return;
        }
        frame = 0;
        drawFrame(frames);
        frameTimer = setTimeout(advance, next === 'idle' ? IDLE_REST_MS : frameDelay);
        return;
      }
      drawFrame(frames);
      frameTimer = setTimeout(advance, frameDelay);
    };
    frameTimer = setTimeout(advance, startWithRest && next === 'idle' ? IDLE_REST_MS : frameDelay);
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
      startClientY: event.clientY,
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
    const startedInNotchZone = docked && pointer.startClientY <= 44;
    pointer = null;
    dragging = false;
    document.body.classList.remove('is-dragging');
    if (wasDragging) {
      window.paimonPetAPI.endDrag();
    } else if (startedInNotchZone) {
      window.paimonPetAPI.openWorkspace();
    } else {
      void play('clicking', { once: true });
      window.paimonPetAPI.openAssistant();
    }
  }

  stage.addEventListener('pointerup', finishPointer);
  stage.addEventListener('pointercancel', finishPointer);

  window.paimonPetAPI.onMode((payload) => {
    const mode = payload && payload.mode || 'idle';
    docked = payload && payload.docked === true;
    stage.classList.toggle('is-docked', docked);
    if (mode === 'docking') {
      stage.classList.add('is-docking');
      return;
    }
    stage.classList.remove('is-docking');
    void play(['idle', 'listening', 'speaking', 'clicking'].includes(mode) ? mode : 'idle', {
      startWithRest: mode === 'idle',
    });
  });

  void play(animation, { startWithRest: true });
})();
