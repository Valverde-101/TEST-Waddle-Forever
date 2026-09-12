import { addDispatchEventListeners } from '@common/utils';
import { ipcRenderer } from 'electron';

addDispatchEventListeners([
  'get-players',
  'get-command-center-data',
  'command-result'
], ipcRenderer);

(window as any).api = {
  fetchPlayers: () => ipcRenderer.send('get-players'),
  fetchCommandCenterData: () => ipcRenderer.send('get-command-center-data'),
  openCommandsList: () => ipcRenderer.send('open-commands-list'),
  runCommand: (obj: any) => ipcRenderer.send('run-command', obj)
};
