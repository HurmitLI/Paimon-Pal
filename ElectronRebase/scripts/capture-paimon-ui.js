#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const outputDirectory = path.join(__dirname, '..', 'docs', 'qa');
const cdpPort = Number(process.env.PAIMON_CDP_PORT || 9223);

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
    await mainClient.send('Page.enable');
    await petClient.send('Page.enable');
    const wasExpanded = await evaluate(mainClient, `document.getElementById('app').classList.contains('expanded')`);
    if (wasExpanded) {
      await evaluate(mainClient, `document.querySelector('.topbar').click()`);
      await new Promise((resolve) => setTimeout(resolve, 700));
    }
    await evaluate(mainClient, `document.getElementById('notch').click()`);
    await new Promise((resolve) => setTimeout(resolve, 850));
    const expanded = await evaluate(mainClient, `document.getElementById('app').classList.contains('expanded')`);
    if (!expanded) throw new Error('notch workspace did not expand');
    const expandedPath = await capture(mainClient, 'paimon-pal-expanded.png');

    await evaluate(mainClient, `document.getElementById('paimon-top-trigger').click()`);
    await new Promise((resolve) => setTimeout(resolve, 250));
    const assistantVisible = await evaluate(mainClient, `!document.getElementById('paimon-assistant').hidden`);
    if (!assistantVisible) throw new Error('assistant composer did not open');
    const assistantPath = await capture(mainClient, 'paimon-pal-assistant.png');

    await evaluate(mainClient, `(() => {
      const input = document.getElementById('paimon-input');
      input.value = '帮我计时 1 分钟';
      document.getElementById('paimon-composer').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    })()`);
    await new Promise((resolve) => setTimeout(resolve, 350));
    const timerReply = await evaluate(mainClient, `document.getElementById('paimon-reply').textContent`);
    if (!/计时已经开始/.test(timerReply)) throw new Error(`timer tool failed: ${timerReply}`);
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
    const modelPath = await capture(mainClient, 'paimon-pal-local-4b.png');

    await evaluate(mainClient, `window.notchAPI.detachPet()`);
    await new Promise((resolve) => setTimeout(resolve, 180));
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
    if (process.env.PAIMON_TEST_TTS === '1') {
      const ttsResult = await evaluate(mainClient, `window.notchAPI.speakPaimon('你好，今天也一起加油吧。')`);
      if (!ttsResult || !ttsResult.ok || !ttsResult.base64) throw new Error(`local TTS failed: ${JSON.stringify(ttsResult)}`);
      ttsBytes = Math.floor(ttsResult.base64.length * 3 / 4);
      if (ttsBytes < 20_000) throw new Error(`local TTS output is unexpectedly small: ${ttsBytes}`);
    }
    console.log(JSON.stringify({
      ok: true,
      expandedPath,
      assistantPath,
      timerPath,
      modelPath,
      petPath,
      timerReply,
      modelReply,
      petStart,
      petEnd,
      ttsBytes,
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
