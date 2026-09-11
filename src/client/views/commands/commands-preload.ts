import { addDispatchEventListeners } from '@common/utils';
import { ipcRenderer } from 'electron';

addDispatchEventListeners(
  ['get-players', 'command-center-data', 'command-result'],
  ipcRenderer
);

(window as any).api = {
  fetchPlayers: () => ipcRenderer.send('get-players'),
  fetchCommandCenterData: () => ipcRenderer.send('get-command-center-data'),
  runCommand: (obj: { id: number; command: string }) => ipcRenderer.send('run-command', obj)
};
