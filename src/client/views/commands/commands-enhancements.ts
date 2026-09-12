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
const TARGET_KEY = 'waddle-command-center-target-v1';

let lastTargets: CommandTargetInfo[] = [];

const getSelectedCommandCode = (): string => {
  const selected = document.querySelector('.command-list-item.selected .command-code');
  return selected?.textContent?.trim() || '';
};

const normalizeTargets = (value: unknown): CommandTargetInfo[] => {
  if (!Array.isArray(value)) return [];

  const byId = new Map<number, CommandTargetInfo>();
  for (const raw of value) {
    if (raw === null || typeof raw !== 'object') continue;
    const candidate = raw as Partial<CommandTargetInfo>;
    const id = Number(candidate.id);
    const name = typeof candidate.name === 'string' ? candidate.name.trim() : '';
    if (!Number.isInteger(id) || id <= 0 || name === '') continue;

    const existing = byId.get(id);
    if (existing !== undefined) {
      existing.name = name;
      existing.online = existing.online === true || candidate.online === true;
      existing.saved = existing.saved === true || candidate.saved === true;
      continue;
    }

    byId.set(id, {
      id,
      name,
      online: candidate.online === true,
      saved: candidate.saved === true
    });
  }

  return Array.from(byId.values()).sort((a, b) => {
    if (a.online !== b.online) return a.online ? -1 : 1;
    return a.name.localeCompare(b.name) || a.id - b.id;
  });
};

const getSelectedTarget = (): CommandTargetInfo | undefined => {
  if (enhancedPlayerSelect === null || enhancedPlayerSelect.selectedIndex < 0) return undefined;
  const id = Number(enhancedPlayerSelect.value);
  if (!Number.isInteger(id) || id <= 0) return undefined;
  return lastTargets.find(target => target.id === id);
};

const updateTargetStatus = () => {
  if (enhancedPlayerStatus === null || enhancedConnectionState === null) return;

  if (lastTargets.length === 0) {
    enhancedPlayerStatus.textContent = 'No saved or online penguins found';
    enhancedConnectionState.classList.remove('online');
    return;
  }

  const online = lastTargets.filter(player => player.online === true).length;
  const saved = lastTargets.filter(player => player.saved === true).length;
  const selected = getSelectedTarget();
  const selectedText = selected === undefined ? ' · no target selected' : ` · ${selected.name} selected`;

  enhancedPlayerStatus.textContent = `${online} online · ${saved} saved profile${saved === 1 ? '' : 's'}${selectedText}`;
  enhancedConnectionState.classList.toggle('online', online > 0);
};

const reconcilePlayerSelect = (rawTargets: unknown) => {
  if (enhancedPlayerSelect === null) return;

  const targets = normalizeTargets(rawTargets);
  lastTargets = targets;

  const current = enhancedPlayerSelect.value.trim();
  let remembered = '';
  try {
    remembered = localStorage.getItem(TARGET_KEY) || '';
  } catch {
    remembered = '';
  }

  enhancedPlayerSelect.replaceChildren();

  if (targets.length === 0) {
    const option = document.createElement('option');
    option.value = '';
    option.textContent = 'No penguin profiles found';
    option.selected = true;
    enhancedPlayerSelect.appendChild(option);
    enhancedPlayerSelect.disabled = true;
    updateTargetStatus();
    return;
  }

  for (const target of targets) {
    const option = document.createElement('option');
    option.value = String(target.id);
    const states = [target.online ? 'ONLINE' : '', target.saved ? 'SAVED' : ''].filter(Boolean).join(' + ') || 'AVAILABLE';
    option.textContent = `${target.name}  ·  #${target.id}  ·  ${states}`;
    enhancedPlayerSelect.appendChild(option);
  }

  const requested = [current, remembered]
    .find(value => value !== '' && targets.some(target => String(target.id) === value));

  if (requested !== undefined) {
    enhancedPlayerSelect.value = requested;
  } else {
    enhancedPlayerSelect.selectedIndex = 0;
    enhancedPlayerSelect.value = String(targets[0].id);
  }

  // Chromium 85 occasionally left a dynamically rebuilt <select> with no
  // selected option when several async refreshes arrived close together. Do
  // not rely on implicit browser selection: assert a real option and value.
  if (enhancedPlayerSelect.selectedIndex < 0 || enhancedPlayerSelect.value === '') {
    enhancedPlayerSelect.selectedIndex = 0;
  }

  const selectedOption = enhancedPlayerSelect.options[enhancedPlayerSelect.selectedIndex];
  if (selectedOption !== undefined) {
    selectedOption.selected = true;
    try {
      localStorage.setItem(TARGET_KEY, selectedOption.value);
    } catch {
      // A writable localStorage is convenient, never required for selection.
    }
  }

  enhancedPlayerSelect.disabled = false;
  updateTargetStatus();
};

window.addEventListener('get-players', (event: Event) => {
  reconcilePlayerSelect((event as CustomEvent).detail);
});

if (enhancedPlayerSelect !== null) {
  enhancedPlayerSelect.addEventListener('change', () => {
    const selected = getSelectedTarget();
    if (selected !== undefined) {
      try {
        localStorage.setItem(TARGET_KEY, String(selected.id));
      } catch {
        // Selection itself is already valid even if persistence is unavailable.
      }
    }
    updateTargetStatus();
  });
}

window.addEventListener('command-center-player-error', (event: Event) => {
  if (enhancedPlayerStatus === null || enhancedConnectionState === null || enhancedPlayerSelect === null) return;
  enhancedPlayerSelect.disabled = true;
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
