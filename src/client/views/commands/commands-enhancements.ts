const enhancedCommandInput = document.getElementById('command-input') as HTMLInputElement | null;
const enhancedCommandButton = document.getElementById('command-button');

const getSelectedCommandCode = (): string => {
  const selected = document.querySelector('.command-list-item.selected .command-code');
  return selected?.textContent?.trim() || '';
};

// Keep this file strictly additive. Player selection has one owner only:
// commands-static.ts. The previous implementation also listened for
// `get-players` and rebuilt the same <select> a second time for every refresh,
// creating a race on Chromium 85 where the selected option could disappear.
//
// This enhancement only makes the raw command preview forgiving. If Coins is
// selected and the user types just "1000", normalize it to "ac 1000" before
// the primary click handler reads the value.
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
