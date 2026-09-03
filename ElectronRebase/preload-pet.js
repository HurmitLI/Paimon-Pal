const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('paimonPetAPI', {
  beginDrag: (screenX, screenY) => ipcRenderer.send('pet:begin-drag', { screenX, screenY }),
  dragTo: (screenX, screenY) => ipcRenderer.send('pet:drag-to', { screenX, screenY }),
  endDrag: () => ipcRenderer.send('pet:end-drag'),
  openAssistant: () => ipcRenderer.send('pet:open-assistant'),
  openWorkspace: () => ipcRenderer.send('pet:open-workspace'),
  onMode: (callback) => {
    const handler = (event, payload) => callback(payload);
    ipcRenderer.on('pet:mode', handler);
    return () => ipcRenderer.removeListener('pet:mode', handler);
  },
});
