type CommandTargetInfo = {
  id: number;
  name: string;
  online?: boolean;
  saved?: boolean;
};

const enhancedPlayerSelect = document.getElementById('player-select') as HTMLSelectElement | null;
const enhancedPlayerStatus = document.getElementById('player-status');
const enhancedConnectionState = document.getElementById('connection-state');
const enhancedCommandInput = document.getElementById('command-input') as HTMLInputElement | null;
const enhancedCommandButton = document.getElementById('command-button');

const getSelectedCommandCode = (): string => {
  const selected = document.querySelector('.command-list-item.selected .command-code');
  return selected?.textContent?.trim() || '';
};

window.addEventListener('get-players', (event: Event) => {
  if (enhancedPlayerSelect === null || enhancedPlayerStatus === null || enhancedConnectionState === null) return;

  const players = (event as CustomEvent).detail as CommandTargetInfo[];
  const options = Array.from(enhancedPlayerSelect.options);

  players.forEach((player, index) => {
    const option = options[index];
    if (option === undefined) return;
    const state = player.online ? 'ONLINE' : player.saved ? 'SAVED' : 'AVAILABLE';
    option.textContent = `${player.name}  ·  #${player.id}  ·  ${state}`;
  });

  if (players.length === 0) {
    enhancedPlayerStatus.textContent = 'No saved or online penguins found';
    enhancedConnectionState.classList.remove('online');
    return;
  }

  const online = players.filter(player => player.online).length;
  const saved = players.filter(player => player.saved).length;
  enhancedPlayerStatus.textContent = `${online} online · ${saved} saved profile${saved === 1 ? '' : 's'}`;
  enhancedConnectionState.classList.toggle('online', online > 0);
});

window.addEventListener('command-center-player-error', (event: Event) => {
  if (enhancedPlayerStatus === null || enhancedConnectionState === null) return;
  enhancedPlayerStatus.textContent = `Player lookup failed: ${String((event as CustomEvent).detail)}`;
  enhancedConnectionState.classList.remove('online');
});

// The raw preview is intentionally forgiving. If the user has already selected
// Coins and types only "1000", treat that as "ac 1000" instead of reporting
// "Unknown command: 1000". The same behavior applies to other selected actions.
if (enhancedCommandButton !== null && enhancedCommandInput !== null) {
  enhancedCommandButton.addEventListener('click', () => {
    const raw = enhancedCommandInput.value.trim();
    const selectedCode = getSelectedCommandCode();
    if (raw === '' || selectedCode === '') return;

    const firstToken = raw.match(/^(\w+)/)?.[1] || '';
    const knownCodes = new Set(Array.from(document.querySelectorAll('.command-code'))
      .map(element => element.textContent?.trim() || '')
      .filter(Boolean));

    if (!knownCodes.has(firstToken)) {
      enhancedCommandInput.value = `${selectedCode} ${raw}`;
    }
  }, true);
}
