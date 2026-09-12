import { ipcRenderer } from 'electron';

(window as any).api = {
  fetchPlayers: () => ipcRenderer.invoke('command-center:get-players'),
  fetchCommandCenterData: () => ipcRenderer.invoke('command-center:get-data'),
  openCommandsList: () => ipcRenderer.send('open-commands-list'),
  runCommand: (obj: any) => ipcRenderer.invoke('command-center:run-command', obj)
};
