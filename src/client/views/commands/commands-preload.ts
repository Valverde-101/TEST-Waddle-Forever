import { ipcRenderer } from 'electron';

const dispatch = (name: string, detail: unknown) => {
  window.dispatchEvent(new CustomEvent(name, { detail }));
};

const fetchCommandCenterData = async () => {
  try {
    const data = await ipcRenderer.invoke('command-center:get-data');
    dispatch('get-command-center-data', data);
    return data;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    dispatch('command-center-data-error', message);
    return undefined;
  }
};

const fetchState = async () => {
  try {
    const state = await ipcRenderer.invoke('command-center:get-state');
    dispatch('command-center-state', state);
    return state;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    dispatch('command-center-state-error', message);
    return undefined;
  }
};

const searchCatalog = async (obj: any) => {
  try {
    return await ipcRenderer.invoke('command-center:search-catalog', obj);
  } catch (error) {
    dispatch('command-center-catalog-error', error instanceof Error ? error.message : String(error));
    return [];
  }
};

const runCommand = async (obj: any) => {
  try {
    const result = await ipcRenderer.invoke('command-center:run-command', obj);
    dispatch('command-result', result);
    void fetchState();
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
  fetchCommandCenterData,
  fetchState,
  searchCatalog,
  openCommandsList: () => ipcRenderer.send('open-commands-list'),
  runCommand
};
