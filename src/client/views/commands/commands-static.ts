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
};

type CommandResult = {
  ok: boolean;
  command?: string;
  message: string;
};

type CoinMode = 'add' | 'remove';

const commandsApi = (window as any).api;

const actionsButton = document.getElementById('actions-button')!;
const moreActionsButton = document.getElementById('more-actions-button')!;
const commandsListButton = document.getElementById('commandslist-button')!;
const actionDrawer = document.getElementById('action-drawer')!;
const drawerBackdrop = document.getElementById('drawer-backdrop')!;
const drawerClose = document.getElementById('drawer-close')!;
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
const commandButton = document.getElementById('command-button')! as HTMLButtonElement;
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
const advancedDetails = document.getElementById('advanced-details')! as HTMLDetailsElement;
const coinControls = document.getElementById('coin-controls')!;
const coinAmount = document.getElementById('coin-amount')! as HTMLInputElement;

const HISTORY_KEY = 'waddle-command-center-history-v3';
const FAVORITES_KEY = 'waddle-command-center-favorites-v1';
const MAX_HISTORY = 12;

let commandData: CommandCenterData = { commands: [] };
let selectedCommand: CommandInfo | null = null;
let argumentInputs: HTMLInputElement[] = [];
let commandHistory: string[] = readStringArray(HISTORY_KEY);
let favorites = new Set(readStringArray(FAVORITES_KEY));
let catalogSearchTimer: ReturnType<typeof setTimeout> | null = null;
let catalogRequestSequence = 0;
let coinMode: CoinMode = 'add';

function clearElement(element: Element) {
  while (element.firstChild !== null) {
    element.removeChild(element.firstChild);
  }
}

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

function openDrawer() {
  actionDrawer.classList.remove('hidden');
  drawerBackdrop.classList.remove('hidden');
  document.body.classList.add('drawer-open');
  window.setTimeout(() => {
    commandSearch.focus();
    commandSearch.select();
  }, 0);
}

function closeDrawer() {
  actionDrawer.classList.add('hidden');
  drawerBackdrop.classList.add('hidden');
  document.body.classList.remove('drawer-open');
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

function renderCategories() {
  const selected = categorySelect.value || 'all';
  const categories = Array.from(new Set(commandData.commands.map(command => categoryFor(command.name)))).sort();
  clearElement(categorySelect);

  const all = document.createElement('option');
  all.value = 'all';
  all.textContent = 'All categories';
  categorySelect.appendChild(all);

  const favoriteOption = document.createElement('option');
  favoriteOption.value = 'favorites';
  favoriteOption.textContent = '★ Favorites';
  categorySelect.appendChild(favoriteOption);

  for (const category of categories) {
    const option = document.createElement('option');
    option.value = category;
    option.textContent = category;
    categorySelect.appendChild(option);
  }

  const valid = selected === 'all' || selected === 'favorites' || categories.includes(selected);
  categorySelect.value = valid ? selected : 'all';
}

function renderCommandList() {
  const query = commandSearch.value.trim().toLowerCase();
  const category = categorySelect.value;
  const sorted = commandData.commands.slice().sort((a, b) => {
    const favoriteDelta = Number(favorites.has(b.name)) - Number(favorites.has(a.name));
    if (favoriteDelta !== 0) return favoriteDelta;
    return friendlyName(a).localeCompare(friendlyName(b));
  });

  const filtered = sorted.filter(command => {
    if (category === 'favorites' && !favorites.has(command.name)) return false;
    if (category !== 'all' && category !== 'favorites' && categoryFor(command.name) !== category) return false;
    if (!query) return true;
    return [command.name, friendlyName(command), command.description, categoryFor(command.name)]
      .join(' ')
      .toLowerCase()
      .includes(query);
  });

  clearElement(commandList);

  if (filtered.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'drawer-empty';
    empty.textContent = category === 'favorites' ? 'No favorite actions yet.' : 'No actions match this search.';
    commandList.appendChild(empty);
    return;
  }

  for (const command of filtered) {
    const button = document.createElement('button');
    button.className = 'command-list-item';
    button.type = 'button';
    button.title = command.description.replace(/\s+/g, ' ').trim();
    if (selectedCommand && selectedCommand.name === command.name) button.classList.add('selected');

    const name = document.createElement('strong');
    name.textContent = `${favorites.has(command.name) ? '★ ' : ''}${friendlyName(command)}`;

    const code = document.createElement('span');
    code.className = 'command-code';
    code.textContent = command.name;

    const category = document.createElement('small');
    category.textContent = categoryFor(command.name);

    button.append(name, code, category);
    button.addEventListener('click', () => selectCommand(command.name));
    commandList.appendChild(button);
  }
}

function renderHistory() {
  clearElement(historyList);
  if (commandHistory.length === 0) {
    const empty = document.createElement('span');
    empty.className = 'history-empty';
    empty.textContent = 'No commands run yet.';
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

function argumentPlaceholder(command: string, name: string, index: number): string {
  if (command === 'ai' && index === 0) return 'Item ID or all';
  if (command === 'af' && index === 0) return 'Furniture ID';
  if (command === 'af' && index === 1) return 'Quantity (optional)';
  if (command === 'jr' && index === 0) return 'Room ID or name';
  return name || `Argument ${index + 1}`;
}

function updatePreviewFromArguments() {
  if (!selectedCommand || selectedCommand.name === 'ac') return;
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

function updateCoinModeButtons() {
  for (const button of Array.from(document.querySelectorAll<HTMLElement>('[data-coin-mode]'))) {
    button.classList.toggle('active', button.dataset.coinMode === coinMode);
  }
}

function updateCoinPreview() {
  if (!selectedCommand || selectedCommand.name !== 'ac') return;
  const parsed = Math.floor(Math.abs(Number(coinAmount.value)));
  const amount = Number.isFinite(parsed) ? parsed : 0;
  const signed = coinMode === 'remove' ? -amount : amount;
  commandInput.value = `ac ${signed}`;
  commandButton.textContent = coinMode === 'remove' ? 'Remove coins' : 'Add coins';
}

function configureCoinEditor(rawCommand?: string) {
  coinControls.classList.remove('hidden');
  argumentFields.classList.add('hidden');
  coinMode = 'add';
  coinAmount.value = '1000';

  if (rawCommand) {
    const match = rawCommand.trim().match(/^ac\s+(-?\d+)/);
    if (match) {
      const amount = Number(match[1]);
      coinMode = amount < 0 ? 'remove' : 'add';
      coinAmount.value = String(Math.abs(amount));
    }
  }

  updateCoinModeButtons();
  updateCoinPreview();
}

function catalogKindForSelected(): string | null {
  if (!selectedCommand) return null;
  if (selectedCommand.name === 'ai') return 'items';
  if (selectedCommand.name === 'af') return 'furniture';
  if (selectedCommand.name === 'jr') return 'rooms';
  return null;
}

function renderCatalogResults(entries: CatalogEntry[]) {
  clearElement(catalogResults);

  if (entries.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.textContent = 'No catalog entries found.';
    catalogResults.appendChild(empty);
    return;
  }

  for (const entry of entries) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'catalog-result';

    const name = document.createElement('span');
    name.textContent = entry.name;

    const meta = document.createElement('small');
    const cost = typeof entry.cost === 'number' ? ` · ${entry.cost} coins` : '';
    meta.textContent = `ID ${entry.id}${cost}`;

    button.append(name, meta);
    button.addEventListener('click', () => {
      if (argumentInputs.length === 0 || !selectedCommand) return;
      argumentInputs[0].value = selectedCommand.name === 'jr' ? entry.name : String(entry.id);
      updatePreviewFromArguments();
      catalogSearch.value = entry.name;
      clearElement(catalogResults);
      if (argumentInputs.length > 1) argumentInputs[1].focus();
    });
    catalogResults.appendChild(button);
  }
}

async function performCatalogSearch() {
  const kind = catalogKindForSelected();
  if (kind === null) return;

  const sequence = ++catalogRequestSequence;
  const query = catalogSearch.value.trim();
  catalogResults.textContent = 'Searching…';

  const entries = await commandsApi.searchCatalog({ kind, query, limit: 40 });
  if (sequence !== catalogRequestSequence || kind !== catalogKindForSelected()) return;
  renderCatalogResults(Array.isArray(entries) ? entries : []);
}

function scheduleCatalogSearch(immediate = false) {
  if (catalogSearchTimer !== null) clearTimeout(catalogSearchTimer);
  catalogSearchTimer = setTimeout(() => {
    catalogSearchTimer = null;
    void performCatalogSearch();
  }, immediate ? 0 : 140);
}

function renderCatalog() {
  const kind = catalogKindForSelected();
  const enabled = kind !== null;
  catalogSearchWrap.classList.toggle('hidden', !enabled);
  clearElement(catalogResults);
  catalogSearch.value = '';
  catalogRequestSequence += 1;

  if (!enabled || !selectedCommand) return;
  catalogLabel.textContent = selectedCommand.name === 'ai'
    ? 'Find clothing by name or ID'
    : selectedCommand.name === 'af'
      ? 'Find furniture by name or ID'
      : 'Find room by name or ID';
}

function renderExamples(command: CommandInfo) {
  clearElement(examples);
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
  commandDescription.textContent = command.description.replace(/\s+/g, ' ').trim();
  clearElement(argumentFields);
  argumentFields.classList.remove('hidden');
  coinControls.classList.add('hidden');
  argumentInputs = [];
  commandButton.textContent = 'Apply';
  advancedDetails.open = false;

  if (command.name === 'ac') {
    configureCoinEditor(rawCommand);
  } else {
    argumentInputs = command.argNames.map((argName, index) => makeArgumentField(argName, index));
    const parts = rawCommand ? rawCommand.trim().split(/\s+/) : [];
    if (parts.length > 0 && parts[0] === command.name) {
      const args = parts.slice(1);
      argumentInputs.forEach((input, index) => {
        input.value = args[index] || '';
      });
    }
    updatePreviewFromArguments();
    if (rawCommand) commandInput.value = rawCommand.trim();
  }

  updateFavoriteButton();
  renderCatalog();
  renderExamples(command);
  setStatus('Ready');
  renderCommandList();
  closeDrawer();

  if (command.name === 'ac') {
    coinAmount.focus();
    coinAmount.select();
  } else if (catalogKindForSelected() !== null) {
    catalogSearch.focus();
  } else if (argumentInputs.length > 0) {
    argumentInputs[0].focus();
  }
}

function loadRawCommand(rawCommand: string) {
  const trimmed = rawCommand.trim();
  const match = trimmed.match(/^(\w+)/);
  if (!match) return;

  const name = match[1];
  if (commandData.commands.some(command => command.name === name)) {
    selectCommand(name, trimmed);
    return;
  }

  commandInput.value = trimmed;
  advancedDetails.open = true;
  setStatus('Raw command loaded');
}

function normalizeCommandInput(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed === '') return '';
  const first = trimmed.match(/^(\w+)/)?.[1] || '';
  if (commandData.commands.some(info => info.name === first)) return trimmed;
  if (selectedCommand) return `${selectedCommand.name} ${trimmed}`.trim();
  return trimmed;
}

async function runCommand(rawOverride?: string) {
  const command = normalizeCommandInput(rawOverride === undefined ? commandInput.value : rawOverride);
  if (command === '') {
    setStatus('Choose an action first.', 'error');
    return;
  }

  setStatus(`Applying ${command}…`);
  commandButton.setAttribute('disabled', 'disabled');
  const result = await commandsApi.runCommand({ command }) as CommandResult;
  commandButton.removeAttribute('disabled');

  if (!result) {
    setStatus('Command failed without a response.', 'error');
    return;
  }

  if (result.ok) {
    rememberCommand(result.command || command);
    setStatus(result.message, 'success');
  } else {
    setStatus(result.message, 'error');
  }
}

window.addEventListener('get-command-center-data', (event: Event) => {
  const data = (event as CustomEvent).detail as CommandCenterData;
  commandData = data && Array.isArray(data.commands) ? data : { commands: [] };
  renderCategories();
  renderCommandList();

  if (commandData.commands.some(command => command.name === 'ac')) {
    selectCommand('ac');
  }
});

window.addEventListener('command-center-data-error', (event: Event) => {
  setStatus(String((event as CustomEvent).detail || 'Unable to load commands.'), 'error');
});

window.addEventListener('command-center-catalog-error', (event: Event) => {
  catalogResults.textContent = String((event as CustomEvent).detail || 'Catalog search failed.');
});

actionsButton.addEventListener('click', openDrawer);
moreActionsButton.addEventListener('click', openDrawer);
drawerClose.addEventListener('click', closeDrawer);
drawerBackdrop.addEventListener('click', closeDrawer);
commandsListButton.addEventListener('click', () => commandsApi.openCommandsList());
commandSearch.addEventListener('input', renderCommandList);
categorySelect.addEventListener('change', renderCommandList);
catalogSearch.addEventListener('input', () => scheduleCatalogSearch());
commandButton.addEventListener('click', () => void runCommand());

for (const button of Array.from(document.querySelectorAll<HTMLElement>('[data-command]'))) {
  button.addEventListener('click', () => {
    const command = button.dataset.command || '';
    if (command === '') return;
    loadRawCommand(command);
    void runCommand(command);
  });
}

for (const button of Array.from(document.querySelectorAll<HTMLElement>('[data-select-command]'))) {
  button.addEventListener('click', () => {
    const name = button.dataset.selectCommand || '';
    if (name !== '') selectCommand(name);
  });
}

for (const button of Array.from(document.querySelectorAll<HTMLElement>('[data-coin-mode]'))) {
  button.addEventListener('click', () => {
    coinMode = button.dataset.coinMode === 'remove' ? 'remove' : 'add';
    updateCoinModeButtons();
    updateCoinPreview();
  });
}

for (const button of Array.from(document.querySelectorAll<HTMLElement>('[data-coin-value]'))) {
  button.addEventListener('click', () => {
    const value = Number(button.dataset.coinValue || '0');
    if (!Number.isFinite(value) || value < 0) return;
    coinAmount.value = String(Math.floor(value));
    updateCoinPreview();
  });
}

coinAmount.addEventListener('input', updateCoinPreview);

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

document.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault();
    openDrawer();
  }

  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
    event.preventDefault();
    void runCommand();
  }

  if (event.key === 'Escape' && !actionDrawer.classList.contains('hidden')) {
    closeDrawer();
  }
});

window.addEventListener('load', () => {
  renderHistory();
  void commandsApi.fetchCommandCenterData();
});
