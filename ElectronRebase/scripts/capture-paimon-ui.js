#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const outputDirectory = path.join(__dirname, '..', 'docs', 'qa');
const cdpPort = Number(process.env.PAIMON_CDP_PORT || 9223);
const debugCapture = process.env.PAIMON_DEBUG_CAPTURE === '1';
const trace = (message) => { if (debugCapture) console.error(`[qa] ${message}`); };

async function targets() {
  const response = await fetch(`http://127.0.0.1:${cdpPort}/json/list`);
  return response.json();
}

async function connect(target) {
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  let sequence = 0;
  const pending = new Map();
  socket.on('message', (data) => {
    const message = JSON.parse(String(data));
    if (!message.id || !pending.has(message.id)) return;
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message));
    else resolve(message.result);
  });
  return {
    send(method, params = {}) {
      const id = ++sequence;
      socket.send(JSON.stringify({ id, method, params }));
      return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
    },
    close() { socket.close(); },
  };
}

async function evaluate(client, expression, awaitPromise = true) {
  const result = await client.send('Runtime.evaluate', {
    expression,
    awaitPromise,
    returnByValue: true,
  });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || 'evaluation failed');
  return result.result && result.result.value;
}

async function capture(client, name) {
  const result = await client.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  const filePath = path.join(outputDirectory, name);
  fs.mkdirSync(outputDirectory, { recursive: true });
  fs.writeFileSync(filePath, Buffer.from(result.data, 'base64'));
  return filePath;
}

async function main() {
  const pages = await targets();
  const mainTarget = pages.find((item) => item.title === 'Paimon Pal');
  const petTarget = pages.find((item) => item.title === '派蒙桌面伙伴');
  if (!mainTarget || !petTarget) throw new Error('Paimon Pal DevTools targets are unavailable');

  const mainClient = await connect(mainTarget);
  const petClient = await connect(petTarget);
  try {
    trace('connected');
    await mainClient.send('Page.enable');
    await petClient.send('Page.enable');
    const wasAssistantOnly = await evaluate(mainClient, `document.getElementById('app').classList.contains('assistant-only')`);
    if (wasAssistantOnly) {
      await evaluate(mainClient, `document.getElementById('paimon-close').click()`);
      await new Promise((resolve) => setTimeout(resolve, 450));
    }
    await evaluate(mainClient, `window.notchAPI.dockPet()`);
    await new Promise((resolve) => setTimeout(resolve, 350));
    trace('pet docked');
    const wasExpanded = await evaluate(mainClient, `document.getElementById('app').classList.contains('expanded')`);
    if (wasExpanded) {
      await evaluate(mainClient, `document.querySelector('.topbar').click()`);
      await new Promise((resolve) => setTimeout(resolve, 700));
    }
    await evaluate(mainClient, `document.getElementById('notch').click()`);
    await new Promise((resolve) => setTimeout(resolve, 850));
    const expanded = await evaluate(mainClient, `document.getElementById('app').classList.contains('expanded')`);
    if (!expanded) throw new Error('notch workspace did not expand');
    trace('workspace expanded');
    const expandedPath = await capture(mainClient, 'paimon-pal-expanded.png');

    await evaluate(mainClient, `document.getElementById('paimon-top-trigger').click()`);
    const assistantDeadline = Date.now() + 4_000;
    let assistantReady = false;
    while (Date.now() < assistantDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 50));
      assistantReady = await evaluate(mainClient, `(() => {
        const app = document.getElementById('app');
        const panel = document.getElementById('paimon-assistant');
        const rect = panel.getBoundingClientRect();
        return app.classList.contains('assistant-only')
          && (app.classList.contains('assistant-anchor-left') || app.classList.contains('assistant-anchor-right'))
          && !panel.hidden
          && rect.right <= innerWidth
          && rect.bottom <= innerHeight;
      })()`);
      if (assistantReady) break;
    }
    if (!assistantReady) throw new Error('assistant-only surface did not open');
    trace('assistant-only surface opened');
    const assistantVisible = await evaluate(mainClient, `!document.getElementById('paimon-assistant').hidden`);
    if (!assistantVisible) throw new Error('assistant composer did not open');
    const assistantGeometry = await evaluate(mainClient, `(() => {
      const panel = document.getElementById('paimon-assistant').getBoundingClientRect();
      return {
        panel: { x: panel.x, y: panel.y, width: panel.width, height: panel.height, right: panel.right, bottom: panel.bottom },
        viewport: { x: screenX, y: screenY, width: innerWidth, height: innerHeight },
        appClass: document.getElementById('app').className,
        topbarDisplay: getComputedStyle(document.querySelector('.topbar')).display
      };
    })()`);
    const petGeometry = await evaluate(petClient, `({
      x: screenX,
      y: screenY,
      width: innerWidth,
      height: innerHeight,
      visible: document.visibilityState === 'visible'
    })`);
    if (!assistantGeometry.appClass.includes('assistant-only') || assistantGeometry.appClass.includes('expanded')) {
      throw new Error(`assistant incorrectly opened the full workspace: ${JSON.stringify(assistantGeometry)}`);
    }
    if (assistantGeometry.topbarDisplay !== 'none' || assistantGeometry.viewport.width > 430) {
      throw new Error(`workspace toolbar leaked into assistant surface: ${JSON.stringify(assistantGeometry)}`);
    }
    if (assistantGeometry.panel.x < 0 || assistantGeometry.panel.y < 0
      || assistantGeometry.panel.right > assistantGeometry.viewport.width
      || assistantGeometry.panel.bottom > assistantGeometry.viewport.height) {
      throw new Error(`assistant escaped its compact surface: ${JSON.stringify(assistantGeometry)}`);
    }
    const surfaceRight = assistantGeometry.viewport.x + assistantGeometry.viewport.width;
    const petRight = petGeometry.x + petGeometry.width;
    const adjacent = Math.abs(assistantGeometry.viewport.x - (petRight - 24)) <= 3
      || Math.abs(surfaceRight - (petGeometry.x + 24)) <= 3;
    if (!petGeometry.visible || !adjacent) {
      throw new Error(`assistant is not adjacent to Paimon: ${JSON.stringify({ assistantGeometry, petGeometry })}`);
    }
    const assistantPath = await capture(mainClient, 'paimon-pal-assistant.png');
    trace('assistant geometry captured');

    await evaluate(mainClient, `(() => {
      const input = document.getElementById('paimon-input');
      input.value = '帮我计时 1 分钟';
      document.getElementById('paimon-composer').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    })()`);
    await new Promise((resolve) => setTimeout(resolve, 350));
    const timerReply = await evaluate(mainClient, `document.getElementById('paimon-reply').textContent`);
    if (!/计时已经开始/.test(timerReply)) throw new Error(`timer tool failed: ${timerReply}`);
    trace('timer tool passed');
    const timerPath = await capture(mainClient, 'paimon-pal-timer-tool.png');

    await evaluate(mainClient, `(() => {
      const input = document.getElementById('paimon-input');
      input.value = '1加1等于多少？只回答数字。';
      document.getElementById('paimon-composer').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    })()`);
    const modelDeadline = Date.now() + 30_000;
    let modelReply = '';
    while (Date.now() < modelDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      const snapshot = await evaluate(mainClient, `({
        status: document.getElementById('paimon-assistant-status').textContent,
        reply: document.getElementById('paimon-reply').textContent
      })`);
      if (snapshot.status !== '正在想…') {
        modelReply = snapshot.reply;
        break;
      }
    }
    if (modelReply.trim() !== '2') throw new Error(`local 4B model failed: ${modelReply}`);
    trace('local model passed');
    const modelPath = await capture(mainClient, 'paimon-pal-local-4b.png');

    await evaluate(mainClient, `window.notchAPI.detachPet()`);
    await new Promise((resolve) => setTimeout(resolve, 180));
    const petRender = await evaluate(petClient, `(() => {
      const canvas = document.getElementById('pet-sprite');
      return {
        cssWidth: canvas.clientWidth,
        backingWidth: canvas.width,
        pixelRatio: devicePixelRatio,
        firstFrame: canvas.toDataURL()
      };
    })()`);
    if (petRender.backingWidth < Math.round(petRender.cssWidth * petRender.pixelRatio)) {
      throw new Error(`desktop pet is not rendered at Retina resolution: ${JSON.stringify(petRender)}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 700));
    const restedFrame = await evaluate(petClient, `document.getElementById('pet-sprite').toDataURL()`);
    if (restedFrame !== petRender.firstFrame) throw new Error('desktop pet moved continuously during its idle rest');
    const petStart = await evaluate(petClient, `({ x: window.screenX, y: window.screenY })`);
    await evaluate(petClient, `(() => {
      window.paimonPetAPI.beginDrag(100, 100);
      window.paimonPetAPI.dragTo(180, 160);
      window.paimonPetAPI.endDrag();
    })()`);
    await new Promise((resolve) => setTimeout(resolve, 180));
    const petEnd = await evaluate(petClient, `({ x: window.screenX, y: window.screenY })`);
    if (petStart.x === petEnd.x && petStart.y === petEnd.y) throw new Error('desktop pet did not move');
    const petPath = await capture(petClient, 'paimon-pal-pet.png');
    await evaluate(mainClient, `window.notchAPI.dockPet()`);
    let ttsBytes = 0;
    let ttsFirstChunkMs = 0;
    if (process.env.PAIMON_TEST_TTS === '1') {
      const warmResult = await evaluate(mainClient, `window.notchAPI.warmPaimonSpeech()`);
      if (!warmResult || !warmResult.ok) throw new Error(`local TTS warmup failed: ${JSON.stringify(warmResult)}`);
      const ttsResult = await evaluate(mainClient, `new Promise((resolve) => {
        const id = 'qa-tts-' + Date.now();
        let chunks = 0;
        const unsubscribe = window.notchAPI.onPaimonSpeechEvent((event) => {
          if (event && event.id === id && event.type === 'chunk') chunks += 1;
        });
        window.notchAPI.speakPaimon({ id, text: '你好，今天也一起加油吧。' }).then((result) => {
          unsubscribe();
          resolve({ ...result, chunks });
        });
      })`);
      if (!ttsResult || !ttsResult.ok || !ttsResult.streamed || ttsResult.chunks < 1) {
        throw new Error(`local streaming TTS failed: ${JSON.stringify(ttsResult)}`);
      }
      ttsBytes = ttsResult.audioBytes;
      ttsFirstChunkMs = ttsResult.firstChunkMs;
      if (ttsBytes < 20_000) throw new Error(`local TTS output is unexpectedly small: ${ttsBytes}`);
      if (!ttsFirstChunkMs || ttsFirstChunkMs > 2500) throw new Error(`local TTS first chunk is too slow: ${ttsFirstChunkMs}ms`);
    }
    await evaluate(mainClient, `document.getElementById('paimon-close').click()`);
    await new Promise((resolve) => setTimeout(resolve, 350));
    await evaluate(petClient, `window.paimonPetAPI.openAssistant()`);
    const petClickDeadline = Date.now() + 2_000;
    let petClickAssistant = null;
    while (Date.now() < petClickDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 40));
      petClickAssistant = await evaluate(mainClient, `({
        assistantOnly: document.getElementById('app').classList.contains('assistant-only'),
        expanded: document.getElementById('app').classList.contains('expanded'),
        toolbarDisplay: getComputedStyle(document.querySelector('.topbar')).display,
        panelVisible: !document.getElementById('paimon-assistant').hidden,
        width: innerWidth
      })`);
      if (petClickAssistant.assistantOnly && petClickAssistant.panelVisible) break;
    }
    if (!petClickAssistant?.assistantOnly || petClickAssistant.expanded
      || petClickAssistant.toolbarDisplay !== 'none' || petClickAssistant.width > 430) {
      throw new Error(`pet click opened the wrong surface: ${JSON.stringify(petClickAssistant)}`);
    }
    trace('pet click opened only the compact assistant');
    console.log(JSON.stringify({
      ok: true,
      expandedPath,
      assistantPath,
      assistantGeometry,
      petGeometry,
      timerPath,
      modelPath,
      petPath,
      timerReply,
      modelReply,
      petStart,
      petEnd,
      petRender: { cssWidth: petRender.cssWidth, backingWidth: petRender.backingWidth, pixelRatio: petRender.pixelRatio },
      ttsBytes,
      ttsFirstChunkMs,
      petClickAssistant,
    }, null, 2));
  } finally {
    mainClient.close();
    petClient.close();
  }
}

main().catch((error) => {
  console.error(error.stack || error.message);
  process.exitCode = 1;
});
