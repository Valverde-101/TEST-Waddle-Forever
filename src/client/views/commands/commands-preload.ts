import { ipcRenderer } from 'electron';

const dispatch = (name: string, detail: unknown) => {
  window.dispatchEvent(new CustomEvent(name, { detail }));
};

const fetchPlayers = async () => {
  try {
    const players = await ipcRenderer.invoke('command-center:get-players');
    dispatch('get-players', players);
    return players;
  } catch (error) {
    dispatch('command-center-player-error', error instanceof Error ? error.message : String(error));
    throw error;
  }
};

const fetchCommandCenterData = async () => {
  try {
    const data = await ipcRenderer.invoke('command-center:get-data');
    dispatch('get-command-center-data', data);
    return data;
  } catch (error) {
    dispatch('command-center-data-error', error instanceof Error ? error.message : String(error));
    throw error;
  }
};

const runCommand = async (obj: any) => {
  try {
    const result = await ipcRenderer.invoke('command-center:run-command', obj);
    dispatch('command-result', result);
    if (result && result.refreshPlayers) {
      await fetchPlayers();
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

// Do not depend on a one-shot renderer request. A penguin can enter the world
// after Command Center was opened, so keep the selector synchronized for the
// whole lifetime of this popup.
setInterval(() => {
  void fetchPlayers().catch(() => undefined);
}, 1500);
