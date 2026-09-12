type CommandInfo = {
  name: string;
  argNames: string[];
  description: string;
  examples: string[];
};

type CatalogEntry = {
  id: number;
  name: string;
  type?: number;
  cost?: number;
  member?: boolean;
};

type CommandCenterData = {
  commands: CommandInfo[];
  catalog: {
    items: CatalogEntry[];
    furniture: CatalogEntry[];
    rooms: Array<{ id: number; name: string }>;
  };
};

type CommandResult = {
  ok: boolean;
  command?: string;
  message: string;
};

const commandsApi = (window as any).api;

const playerSelect = document.getElementById('player-select')! as HTMLSelectElement;
const playerStatus = document.getElementById('player-status')!;
const connectionState = document.getElementById('connection-state')!;
const refreshButton = document.getElementById('refresh-button')!;
const commandsListButton = document.getElementById('commandslist-button')!;
const commandSearch = document.getElementById('command-search')! as HTMLInputElement;
const categorySelect = document.getElementById('category-select')! as HTMLSelectElement;
const commandList = document.getElementById('command-list')!;
const emptyState = document.getElementById('empty-state')!;
const editorContent = document.getElementById('editor-content')!;
const commandCategory = document.getElementById('command-category')!;
const commandTitle = document.getElementById('command-title')!;
const commandDescription = document.getElementById('command-description')!;
const argumentFields = document.getElementById('argument-fields')!;
const commandInput = document.getElementById('command-input')! as HTMLInputElement;
const commandButton = document.getElementById('command-button')!;
const commandStatus = document.getElementById('command-status')!;
const favoriteButton = document.getElementById('favorite-button')!;
const catalogSearchWrap = document.getElementById('catalog-search-wrap')!;
const catalogLabel = document.getElementById('catalog-label')!;
const catalogSearch = document.getElementById('catalog-search')! as HTMLInputElement;
const catalogResults = document.getElementById('catalog-results')!;
const examplesWrap = document.getElementById('examples-wrap')!;
const examples = document.getElementById('examples')!;
const historyList = document.getElementById('history-list')!;
const clearHistoryButton = document.getElementById('clear-history')!;

const HISTORY_KEY = 'waddle-command-center-history-v1';
const FAVORITES_KEY = 'waddle-command-center-favorites-v1';
const MAX_HISTORY = 12;

let commandData: CommandCenterData = {
  commands: [],
  catalog: { items: [], furniture: [], rooms: [] }
};
let selectedCommand: CommandInfo | null = null;
let argumentInputs: HTMLInputElement[] = [];
let commandHistory: string[] = readStringArray(HISTORY_KEY);
let favorites = new Set(readStringArray(FAVORITES_KEY));

function readStringArray(key: string): string[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || '[]');
    return Array.isArray(parsed) ? parsed.filter(value => typeof value === 'string') : [];
  } catch {
    return [];
  }
}

function saveHistory() {
  localStorage.setItem(HISTORY_KEY, JSON.stringify(commandHistory));
}

function saveFavorites() {
  localStorage.setItem(FAVORITES_KEY, JSON.stringify(Array.from(favorites)));
}

function categoryFor(name: string): string {
  if (name === 'ac') return 'Economy';
  if (name === 'ai' || name === 'af') return 'Inventory';
  if (name === 'jr') return 'Navigation';
  if (name.startsWith('pl')) return 'Puffle Launch';
  if (name === 'amulet' || name === 'cjwin' || name === 'powercards' || name === 'addcard') return 'Card-Jitsu';
  if (name === 'awards') return 'Missions';
  if (name === 'rename' || name === 'age' || name === 'member' || name === 'safechat' || name === 'nosave' || name === 'enablesave') return 'Penguin';
  return 'General';
}

function friendlyName(command: CommandInfo): string {
  const names: Record<string, string> = {
    ac: 'Coins',
    ai: 'Add clothing item',
    af: 'Add furniture',
    jr: 'Teleport to room',
    rename: 'Rename penguin',
    age: 'Reset penguin birthday',
    member: 'Toggle membership',
    awards: 'Mission awards',
    plunlocklevels: 'Unlock Puffle Launch levels',
    plunlocktimeattack: 'Unlock Puffle Launch time attack',
    plunlockturbo: 'Unlock Puffle Launch turbo',
    plunlockslowmode: 'Unlock Puffle Launch slow mode',
    nosave: 'Disable saving',
    enablesave: 'Enable saving',
    amulet: 'Card-Jitsu amulet',
    cjwin: 'Add Card-Jitsu wins',
    powercards: 'Add all power cards',
    addcard: 'Add Card-Jitsu card',
    safechat: 'Toggle safe chat'
  };
  return names[command.name] || command.name;
}

function setStatus(message: string, kind: 'neutral' | 'success' | 'error' = 'neutral') {
  commandStatus.textContent = message;
  commandStatus.classList.remove('neutral', 'success', 'error');
  commandStatus.classList.add(kind);
}

function populatePlayers(players: Array<{ name: string; id: number }>) {
  const previous = playerSelect.value;
  playerSelect.replaceChildren();

  if (players.length === 0) {
    const option = document.createElement('option');
    option.value = '';
    option.textContent = 'No online penguins';
    playerSelect.appendChild(option);
    playerSelect.disabled = true;
    playerStatus.textContent = 'No online penguins';
    connectionState.classList.remove('online');
    return;
  }

  for (const player of players) {
    const option = document.createElement('option');
    option.value = String(player.id);
    option.textContent = `${player.name}  ·  #${player.id}`;
    playerSelect.appendChild(option);
  }

  if (previous && players.some(player => String(player.id) === previous)) {
    playerSelect.value = previous;
  }

  playerSelect.disabled = false;
  playerStatus.textContent = `${players.length} penguin${players.length === 1 ? '' : 's'} online`;
  connectionState.classList.add('online');
}

function renderCategories() {
  const selected = categorySelect.value || 'all';
  const categories = Array.from(new Set(commandData.commands.map(command => categoryFor(command.name)))).sort();
  categorySelect.replaceChildren();

  const all = document.createElement('option');
  all.value = 'all';
  all.textContent = 'All categories';
  categorySelect.appendChild(all);

  for (const category of categories) {
    const option = document.createElement('option');
    option.value = category;
    option.textContent = category;
    categorySelect.appendChild(option);
  }

  categorySelect.value = categories.includes(selected) ? selected : 'all';
}

function renderCommandList() {
  const query = commandSearch.value.trim().toLowerCase();
  const category = categorySelect.value;
  const sorted = [...commandData.commands].sort((a, b) => {
    const favoriteDelta = Number(favorites.has(b.name)) - Number(favorites.has(a.name));
    if (favoriteDelta !== 0) return favoriteDelta;
    return friendlyName(a).localeCompare(friendlyName(b));
  });

  const filtered = sorted.filter(command => {
    const commandCategoryName = categoryFor(command.name);
    if (category !== 'all' && commandCategoryName !== category) return false;
    if (!query) return true;
    return [command.name, friendlyName(command), command.description, commandCategoryName]
      .join(' ')
      .toLowerCase()
      .includes(query);
  });

  commandList.replaceChildren();

  if (filtered.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.textContent = 'No commands match this search.';
    commandList.appendChild(empty);
    return;
  }

  for (const command of filtered) {
    const button = document.createElement('button');
    button.className = 'command-list-item';
    if (selectedCommand && selectedCommand.name === command.name) button.classList.add('selected');
    button.type = 'button';

    const name = document.createElement('strong');
    name.textContent = `${favorites.has(command.name) ? '★ ' : ''}${friendlyName(command)}`;

    const code = document.createElement('span');
    code.className = 'command-code';
    code.textContent = command.name;

    const description = document.createElement('small');
    description.textContent = command.description.replace(/\s+/g, ' ').trim();

    button.append(name, code, description);
    button.addEventListener('click', () => selectCommand(command.name));
    commandList.appendChild(button);
  }
}

function renderHistory() {
  historyList.replaceChildren();
  if (commandHistory.length === 0) {
    const empty = document.createElement('span');
    empty.className = 'history-empty';
    empty.textContent = 'Commands you run will appear here.';
    historyList.appendChild(empty);
    return;
  }

  for (const command of commandHistory) {
    const chip = document.createElement('button');
    chip.type = 'button';
    chip.className = 'history-chip';
    chip.textContent = command;
    chip.title = 'Load this command';
    chip.addEventListener('click', () => loadRawCommand(command));
    historyList.appendChild(chip);
  }
}

function rememberCommand(command: string) {
  commandHistory = [command, ...commandHistory.filter(item => item !== command)].slice(0, MAX_HISTORY);
  saveHistory();
  renderHistory();
}

function updateFavoriteButton() {
  const active = selectedCommand !== null && favorites.has(selectedCommand.name);
  favoriteButton.textContent = active ? '★' : '☆';
  favoriteButton.classList.toggle('active', active);
  favoriteButton.title = active ? 'Remove from favorites' : 'Add to favorites';
}

function updatePreviewFromArguments() {
  if (!selectedCommand) return;
  const args = argumentInputs.map(input => input.value.trim()).filter(value => value !== '');
  commandInput.value = [selectedCommand.name, ...args].join(' ');
}

function makeArgumentField(name: string, index: number): HTMLInputElement {
  const label = document.createElement('label');
  label.className = 'field-group';

  const caption = document.createElement('span');
  caption.textContent = name || `Argument ${index + 1}`;

  const input = document.createElement('input');
  input.type = 'text';
  input.autocomplete = 'off';
  input.placeholder = argumentPlaceholder(selectedCommand ? selectedCommand.name : '', name, index);
  input.addEventListener('input', updatePreviewFromArguments);

  label.append(caption, input);
  argumentFields.appendChild(label);
  return input;
}

function argumentPlaceholder(command: string, name: string, index: number): string {
  if (command === 'ai' && index === 0) return 'Item ID or all';
  if (command === 'af' && index === 0) return 'Furniture ID';
  if (command === 'af' && index === 1) return 'Quantity (optional)';
  if (command === 'jr' && index === 0) return 'Room ID or name';
  if (command === 'ac') return 'Amount, e.g. 10000';
  return name || `Argument ${index + 1}`;
}

function getCatalogForSelected(): CatalogEntry[] | Array<{ id: number; name: string }> {
  if (!selectedCommand) return [];
  if (selectedCommand.name === 'ai') return commandData.catalog.items;
  if (selectedCommand.name === 'af') return commandData.catalog.furniture;
  if (selectedCommand.name === 'jr') return commandData.catalog.rooms;
  return [];
}

function renderCatalogResults() {
  const catalog = getCatalogForSelected();
  const query = catalogSearch.value.trim().toLowerCase();
  catalogResults.replaceChildren();

  if (!selectedCommand || catalog.length === 0) return;

  const matches = catalog
    .filter(entry => {
      if (!query) return true;
      return String(entry.id).includes(query) || entry.name.toLowerCase().includes(query);
    })
    .slice(0, 30);

  for (const entry of matches) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'catalog-result';

    const name = document.createElement('span');
    name.textContent = entry.name;

    const meta = document.createElement('small');
    const cost = 'cost' in entry && typeof entry.cost === 'number' ? ` · ${entry.cost} coins` : '';
    meta.textContent = `ID ${entry.id}${cost}`;

    button.append(name, meta);
    button.addEventListener('click', () => {
      if (argumentInputs.length === 0) return;
      argumentInputs[0].value = selectedCommand!.name === 'jr' ? entry.name : String(entry.id);
      updatePreviewFromArguments();
      catalogSearch.value = entry.name;
      catalogResults.replaceChildren();
      if (argumentInputs.length > 1) argumentInputs[1].focus();
    });
    catalogResults.appendChild(button);
  }

  if (matches.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.textContent = 'No catalog entries found.';
    catalogResults.appendChild(empty);
  }
}

function renderCatalog() {
  const enabled = selectedCommand !== null && ['ai', 'af', 'jr'].includes(selectedCommand.name);
  catalogSearchWrap.classList.toggle('hidden', !enabled);
  catalogResults.replaceChildren();
  catalogSearch.value = '';

  if (!enabled || !selectedCommand) return;
  catalogLabel.textContent = selectedCommand.name === 'ai'
    ? 'Find clothing item by name or ID'
    : selectedCommand.name === 'af'
      ? 'Find furniture by name or ID'
      : 'Find room by name or ID';
  renderCatalogResults();
}

function renderExamples(command: CommandInfo) {
  examples.replaceChildren();
  examplesWrap.classList.toggle('hidden', command.examples.length === 0);
  for (const example of command.examples) {
    const chip = document.createElement('button');
    chip.type = 'button';
    chip.className = 'example-chip';
    chip.textContent = example;
    chip.addEventListener('click', () => loadRawCommand(example));
    examples.appendChild(chip);
  }
}

function selectCommand(name: string, rawCommand?: string) {
  const command = commandData.commands.find(item => item.name === name);
  if (!command) return;

  selectedCommand = command;
  emptyState.classList.add('hidden');
  editorContent.classList.remove('hidden');
  commandCategory.textContent = categoryFor(command.name);
  commandTitle.textContent = friendlyName(command);
  commandDescription.textContent = command.description.trim();
  argumentFields.replaceChildren();
  argumentInputs = command.argNames.map((argName, index) => makeArgumentField(argName, index));
  updateFavoriteButton();
  renderCatalog();
  renderExamples(command);

  const parts = rawCommand ? rawCommand.trim().split(/\s+/) : [];
  if (parts.length > 0 && parts[0] === command.name) {
    const args = parts.slice(1);
    argumentInputs.forEach((input, index) => {
      input.value = args[index] || '';
    });
  }
  updatePreviewFromArguments();
  if (rawCommand) commandInput.value = rawCommand.trim();
  setStatus('Ready');
  renderCommandList();

  if (argumentInputs.length > 0) argumentInputs[0].focus();
}

function loadRawCommand(rawCommand: string) {
  const trimmed = rawCommand.trim();
  const match = trimmed.match(/^(\w+)/);
  if (!match) return;
  selectCommand(match[1], trimmed);
  commandInput.value = trimmed;
}

function runCommand() {
  const command = commandInput.value.trim();
  const id = Number(playerSelect.value);

  if (!Number.isFinite(id) || playerSelect.disabled) {
    setStatus('No online penguin selected.', 'error');
    return;
  }
  if (!command) {
    setStatus('Choose or enter a command first.', 'error');
    return;
  }

  const name = command.match(/^(\w+)/)?.[1] || '';
  if (!commandData.commands.some(info => info.name === name)) {
    setStatus(`Unknown command: ${name || command}`, 'error');
    return;
  }

  setStatus(`Sending ${command}…`);
  commandsApi.runCommand({ id, command });
}

window.addEventListener('get-players', (event: Event) => {
  const players = (event as CustomEvent).detail as Array<{ name: string; id: number }>;
  populatePlayers(players);
});

window.addEventListener('get-command-center-data', (event: Event) => {
  commandData = (event as CustomEvent).detail as CommandCenterData;
  renderCategories();
  renderCommandList();
  if (!selectedCommand && commandData.commands.length > 0) {
    const initial = commandData.commands.find(command => command.name === 'ac') || commandData.commands[0];
    selectCommand(initial.name);
  }
});

window.addEventListener('command-result', (event: Event) => {
  const result = (event as CustomEvent).detail as CommandResult;
  setStatus(result.message, result.ok ? 'success' : 'error');
  if (result.ok && result.command) rememberCommand(result.command);
});

refreshButton.addEventListener('click', () => commandsApi.fetchPlayers());
commandsListButton.addEventListener('click', () => commandsApi.openCommandsList());
commandSearch.addEventListener('input', renderCommandList);
categorySelect.addEventListener('change', renderCommandList);
catalogSearch.addEventListener('input', renderCatalogResults);
commandButton.addEventListener('click', runCommand);

favoriteButton.addEventListener('click', () => {
  if (!selectedCommand) return;
  if (favorites.has(selectedCommand.name)) favorites.delete(selectedCommand.name);
  else favorites.add(selectedCommand.name);
  saveFavorites();
  updateFavoriteButton();
  renderCommandList();
});

clearHistoryButton.addEventListener('click', () => {
  commandHistory = [];
  saveHistory();
  renderHistory();
});

for (const button of Array.from(document.querySelectorAll<HTMLElement>('.quick-action'))) {
  button.addEventListener('click', () => {
    const raw = button.dataset.command;
    const name = button.dataset.selectCommand;
    if (raw) loadRawCommand(raw);
    else if (name) selectCommand(name);
  });
}

document.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault();
    commandSearch.focus();
    commandSearch.select();
    return;
  }
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
    event.preventDefault();
    runCommand();
  }
});

window.addEventListener('load', () => {
  renderHistory();
  commandsApi.fetchPlayers();
  commandsApi.fetchCommandCenterData();
  commandSearch.focus();
});