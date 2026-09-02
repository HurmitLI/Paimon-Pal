(function initPaimonAssistant() {
  const notch = document.getElementById('notch');
  const trigger = document.getElementById('paimon-top-trigger');
  const panel = document.getElementById('paimon-assistant');
  const closeButton = document.getElementById('paimon-close');
  const detachButton = document.getElementById('paimon-detach');
  const voiceButton = document.getElementById('paimon-voice-toggle');
  const form = document.getElementById('paimon-composer');
  const input = document.getElementById('paimon-input');
  const sendButton = document.getElementById('paimon-send');
  const reply = document.getElementById('paimon-reply');
  const status = document.getElementById('paimon-assistant-status');
  const modelBadge = document.getElementById('paimon-model-badge');
  if (!panel || !input || !form) return;

  const HISTORY_KEY = 'paimon-assistant-history-v3';
  let history = [];
  let busy = false;
  let hoverHideTimer = null;
  let voiceEnabled = false;
  let activeAudio = null;
  let activeAudioUrl = '';

  try {
    voiceEnabled = localStorage.getItem('paimon-voice-enabled-v1') === 'true';
  } catch (error) {
    voiceEnabled = false;
  }

  function updateVoiceButton() {
    if (!voiceButton) return;
    voiceButton.textContent = voiceEnabled ? '语音开' : '语音关';
    voiceButton.setAttribute('aria-pressed', String(voiceEnabled));
  }

  function stopVoice() {
    if (activeAudio) {
      activeAudio.pause();
      activeAudio = null;
    }
    if (activeAudioUrl) {
      URL.revokeObjectURL(activeAudioUrl);
      activeAudioUrl = '';
    }
  }

  async function speak(text) {
    if (!voiceEnabled || !window.notchAPI?.speakPaimon) return;
    stopVoice();
    const previousStatus = status.textContent;
    status.textContent = '正在生成本地声音…';
    try {
      const result = await window.notchAPI.speakPaimon(text);
      if (!result || !result.ok || !result.base64) return;
      const bytes = Uint8Array.from(atob(result.base64), (char) => char.charCodeAt(0));
      activeAudioUrl = URL.createObjectURL(new Blob([bytes], { type: result.mimeType || 'audio/wav' }));
      activeAudio = new Audio(activeAudioUrl);
      activeAudio.addEventListener('ended', stopVoice, { once: true });
      await activeAudio.play();
    } catch (error) {
      // 文本回答已经完成；声音失败不覆盖文字结果。
    } finally {
      status.textContent = previousStatus === '正在想…' ? '只在本机回答' : previousStatus;
    }
  }

  try {
    const stored = JSON.parse(localStorage.getItem(HISTORY_KEY));
    if (Array.isArray(stored)) history = stored.slice(-6);
  } catch (error) {
    history = [];
  }

  function persistHistory() {
    try {
      localStorage.setItem(HISTORY_KEY, JSON.stringify(history.slice(-6)));
    } catch (error) {
      // 本地历史是便利功能，存储额度不足不影响当次对话。
    }
  }

  function setReply(text, tone = '') {
    if (!reply) return;
    reply.hidden = !text;
    reply.textContent = text || '';
    reply.dataset.tone = tone;
  }

  async function ensureExpanded() {
    const app = document.getElementById('app');
    if (app && app.classList.contains('collapsed')) {
      notch?.click();
      await new Promise((resolve) => setTimeout(resolve, 180));
    }
  }

  async function openAssistant() {
    await ensureExpanded();
    panel.hidden = false;
    requestAnimationFrame(() => panel.classList.add('is-visible'));
    setTimeout(() => input.focus({ preventScroll: true }), 40);
  }

  function closeAssistant() {
    stopVoice();
    panel.classList.remove('is-visible');
    setTimeout(() => { panel.hidden = true; }, 160);
  }

  function parseDuration(text) {
    const match = text.match(/(?:计时|倒计时|定时)(?:器)?(?:为|：|:)?\s*(\d{1,4})\s*(小时|分钟|分|秒)/);
    if (!match) return 0;
    const amount = Number(match[1]);
    const unit = match[2];
    const multiplier = unit === '小时' ? 3600 : (unit === '秒' ? 1 : 60);
    const seconds = amount * multiplier;
    return Number.isFinite(seconds) && seconds > 0 && seconds <= 359999 ? seconds : 0;
  }

  function activateTab(name) {
    const button = document.querySelector(`.tab[data-tab="${name}"]`);
    if (!button || button.hidden) return false;
    button.click();
    return true;
  }

  function setTimer(seconds) {
    const minutesInput = document.getElementById('pomodoro-minutes');
    const secondsInput = document.getElementById('pomodoro-seconds');
    const reset = document.getElementById('pomodoro-reset');
    const toggle = document.getElementById('pomodoro-toggle');
    if (!minutesInput || !secondsInput || !toggle) return false;
    if (reset && !reset.hidden) reset.click();
    const minutes = Math.floor(seconds / 60);
    const remain = seconds % 60;
    minutesInput.value = String(minutes).padStart(2, '0');
    secondsInput.value = String(remain).padStart(2, '0');
    minutesInput.dispatchEvent(new Event('change', { bubbles: true }));
    secondsInput.dispatchEvent(new Event('change', { bubbles: true }));
    toggle.click();
    return true;
  }

  function addTodo(text) {
    const match = text.match(/(?:添加|记下|新建)(?:一个)?待办[：:\s]*(.+)$/);
    if (!match || !match[1].trim()) return '';
    const value = match[1].trim().slice(0, 80);
    const todoInput = document.querySelector('.add-row input[data-priority="P3"]');
    if (!todoInput) return '';
    todoInput.value = value;
    todoInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
    return value;
  }

  function saveQuickNote(text) {
    const match = text.match(/(?:记一笔|写个笔记|保存笔记)[：:\s]*(.+)$/);
    if (!match || !match[1].trim()) return '';
    const note = document.getElementById('home-note');
    const save = document.getElementById('note-save-btn');
    if (!note || !save) return '';
    note.value = match[1].trim();
    note.dispatchEvent(new Event('input', { bubbles: true }));
    save.click();
    return note.value;
  }

  function runLocalTool(prompt) {
    const duration = parseDuration(prompt);
    if (duration && setTimer(duration)) {
      const minutes = Math.floor(duration / 60);
      const seconds = duration % 60;
      const label = minutes && seconds ? `${minutes} 分 ${seconds} 秒` : (minutes ? `${minutes} 分钟` : `${seconds} 秒`);
      return `计时已经开始，${label}后提醒你。`;
    }

    const todo = addTodo(prompt);
    if (todo) return `已经把“${todo}”放进日常待办。`;
    const note = saveQuickNote(prompt);
    if (note) return '已经替你保存到随笔记。';

    const tabNames = {
      首页: 'home', 工作台: 'home', 待办: 'todo', 笔记: 'notes', 链接: 'links',
      录制: 'recordings', 录音: 'recordings', 密钥: 'credentials', 剪贴板: 'clip', 设置: 'settings',
    };
    const openMatch = prompt.match(/(?:打开|去|切到)(首页|工作台|待办|笔记|链接|录制|录音|密钥|剪贴板|设置)/);
    if (openMatch && activateTab(tabNames[openMatch[1]])) return `已经打开${openMatch[1]}。`;
    return '';
  }

  async function ask(prompt) {
    if (busy) return;
    const value = String(prompt || '').trim();
    if (!value) return;
    busy = true;
    input.disabled = true;
    sendButton.disabled = true;
    status.textContent = '正在想…';
    setReply('派蒙正在想…', 'loading');
    const context = history.slice(-6);
    history.push({ role: 'user', content: value });
    persistHistory();

    try {
      let answer = runLocalTool(value);
      if (!answer && window.notchAPI?.askPaimon) {
        const result = await window.notchAPI.askPaimon({ prompt: value, history: context });
        if (result && result.ok) answer = result.reply;
        if (!answer && result && result.error === 'model_unavailable') {
          answer = '本地 4B 模型还没有放进当前安装包，但计时、待办、笔记和页面打开仍然可以直接用。';
        }
      }
      if (!answer) answer = '这次本地模型没有成功回答。你可以再说一次，或者先让我帮你计时、记待办和笔记。';
      history.push({ role: 'assistant', content: answer });
      history = history.slice(-6);
      persistHistory();
      setReply(answer);
      void speak(answer);
    } catch (error) {
      setReply('刚才本地模型走神了，工具功能仍可继续使用。', 'error');
    } finally {
      busy = false;
      input.disabled = false;
      sendButton.disabled = false;
      status.textContent = '只在本机回答';
      input.focus({ preventScroll: true });
    }
  }

  trigger?.addEventListener('click', (event) => {
    event.stopPropagation();
    openAssistant();
  });
  closeButton?.addEventListener('click', closeAssistant);
  detachButton?.addEventListener('click', async () => {
    if (window.notchAPI?.detachPet) await window.notchAPI.detachPet();
    closeAssistant();
  });
  voiceButton?.addEventListener('click', () => {
    voiceEnabled = !voiceEnabled;
    try { localStorage.setItem('paimon-voice-enabled-v1', String(voiceEnabled)); } catch (error) {}
    updateVoiceButton();
    if (!voiceEnabled) stopVoice();
    else if (reply && !reply.hidden && reply.textContent && reply.dataset.tone !== 'loading') void speak(reply.textContent);
  });
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const value = input.value;
    input.value = '';
    ask(value);
  });

  notch?.addEventListener('mouseenter', () => {
    if (hoverHideTimer) clearTimeout(hoverHideTimer);
    window.notchAPI?.showDockedPet?.();
  });
  notch?.addEventListener('mouseleave', () => {
    if (hoverHideTimer) clearTimeout(hoverHideTimer);
    hoverHideTimer = setTimeout(() => window.notchAPI?.hideDockedPet?.(), 900);
  });

  window.notchAPI?.onOpenPaimonAssistant?.(openAssistant);
  window.notchAPI?.getPaimonStatus?.().then((result) => {
    if (modelBadge) modelBadge.textContent = result && result.available ? '本地 4B' : '本地工具';
  }).catch(() => {});
  updateVoiceButton();
})();
