import { ipcRenderer } from 'electron';

const dispatch = (name: string, detail: unknown) => {
  window.dispatchEvent(new CustomEvent(name, { detail }));
};

// Preserve the original Waddle command-window contract: the renderer requests
// the current players and the main process pushes the authoritative live list
// back to this exact window. This path does not depend on disk I/O and cannot
// be held hostage by a slow/corrupt saved profile.
ipcRenderer.on('get-players', (_event, players) => {
  dispatch('get-players', players);
});

ipcRenderer.on('command-center-player-error', (_event, message) => {
  dispatch('command-center-player-error', message);
});

const fetchPlayers = () => {
  ipcRenderer.send('get-players');
};

const fetchCommandCenterData = async () => {
  try {
    const data = await ipcRenderer.invoke('command-center:get-data');
    dispatch('get-command-center-data', data);
    return data;
  } catch (error) {
    dispatch('command-center-data-error', error instanceof Error ? error.message : String(error));
    return undefined;
  }
};

const runCommand = async (obj: any) => {
  try {
    const result = await ipcRenderer.invoke('command-center:run-command', obj);
    dispatch('command-result', result);
    if (result && result.refreshPlayers) {
      fetchPlayers();
    }
    return result;
  } catch (error) {
    const result = {
      ok: false,
      message: error instanceof Error ? error.message : String(error)
    };
    dispatch('command-result', result);
    return result;
  }
};

(window as any).api = {
  fetchPlayers,
  fetchCommandCenterData,
  openCommandsList: () => ipcRenderer.send('open-commands-list'),
  runCommand
};
