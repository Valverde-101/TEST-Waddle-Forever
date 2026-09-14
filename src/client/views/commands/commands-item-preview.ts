const processedItemImages = new WeakSet<HTMLImageElement>();
const queuedItemImages = new WeakSet<HTMLImageElement>();
const itemPreviewQueue: HTMLImageElement[] = [];
let itemPreviewQueueRunning = false;
let itemPreviewCount = 0;
let itemPreviewFallbackCount = 0;

const getCardPicture = (image: HTMLImageElement): HTMLElement | null => {
  const parent = image.parentElement;
  return parent instanceof HTMLElement && parent.classList.contains('catalog-card-picture') ? parent : null;
};

const drawTrimmedItemPreview = (image: HTMLImageElement) => {
  if (processedItemImages.has(image)) return;
  processedItemImages.add(image);

  const picture = getCardPicture(image);
  if (picture === null || image.naturalWidth <= 0 || image.naturalHeight <= 0) return;

  try {
    const source = document.createElement('canvas');
    source.width = image.naturalWidth;
    source.height = image.naturalHeight;
    const sourceContext = source.getContext('2d', { willReadFrequently: true } as any) as CanvasRenderingContext2D | null;
    if (sourceContext === null) throw new Error('2D canvas context unavailable');

    sourceContext.clearRect(0, 0, source.width, source.height);
    sourceContext.drawImage(image, 0, 0);
    const pixels = sourceContext.getImageData(0, 0, source.width, source.height).data;

    let minX = source.width;
    let minY = source.height;
    let maxX = -1;
    let maxY = -1;

    for (let y = 0; y < source.height; y += 1) {
      const rowOffset = y * source.width * 4;
      for (let x = 0; x < source.width; x += 1) {
        if (pixels[rowOffset + x * 4 + 3] <= 8) continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    if (maxX < minX || maxY < minY) {
      picture.classList.add('image-missing');
      image.remove();
      return;
    }

    const visibleWidth = maxX - minX + 1;
    const visibleHeight = maxY - minY + 1;
    const sourcePadding = Math.max(3, Math.round(Math.max(visibleWidth, visibleHeight) * 0.08));
    const cropX = Math.max(0, minX - sourcePadding);
    const cropY = Math.max(0, minY - sourcePadding);
    const cropRight = Math.min(source.width, maxX + sourcePadding + 1);
    const cropBottom = Math.min(source.height, maxY + sourcePadding + 1);
    const cropWidth = cropRight - cropX;
    const cropHeight = cropBottom - cropY;

    const preview = document.createElement('canvas');
    preview.className = 'catalog-card-image catalog-card-canvas';
    preview.width = 160;
    preview.height = 160;
    preview.setAttribute('aria-label', image.alt || 'Item preview');

    const previewContext = preview.getContext('2d') as CanvasRenderingContext2D | null;
    if (previewContext === null) throw new Error('Preview canvas context unavailable');

    const targetPadding = 8;
    const maxTarget = preview.width - targetPadding * 2;
    const scale = Math.min(maxTarget / cropWidth, maxTarget / cropHeight);
    const targetWidth = Math.max(1, Math.round(cropWidth * scale));
    const targetHeight = Math.max(1, Math.round(cropHeight * scale));
    const targetX = Math.round((preview.width - targetWidth) / 2);
    const targetY = Math.round((preview.height - targetHeight) / 2);

    previewContext.clearRect(0, 0, preview.width, preview.height);
    previewContext.drawImage(
      image,
      cropX,
      cropY,
      cropWidth,
      cropHeight,
      targetX,
      targetY,
      targetWidth,
      targetHeight
    );

    image.replaceWith(preview);
    picture.classList.add('image-ready', 'image-trimmed');
    picture.classList.remove('image-missing');
    itemPreviewCount += 1;

    if (itemPreviewCount === 1 || itemPreviewCount % 20 === 0) {
      console.log(`WADDLE_COMMAND_CENTER_ITEM_PREVIEW=PASS trimmed=${itemPreviewCount} fallback=${itemPreviewFallbackCount}`);
    }
  } catch (error) {
    image.classList.add('catalog-card-image-raw');
    picture.classList.add('image-ready', 'image-raw');
    itemPreviewFallbackCount += 1;
    console.warn(`WADDLE_COMMAND_CENTER_ITEM_PREVIEW=WARN mode=css-fallback error=${error instanceof Error ? error.message : String(error)}`);
  }
};

const runItemPreviewQueue = () => {
  if (itemPreviewQueueRunning) return;
  itemPreviewQueueRunning = true;

  const next = () => {
    const image = itemPreviewQueue.shift();
    if (image === undefined) {
      itemPreviewQueueRunning = false;
      return;
    }

    if (image.isConnected && image.complete && image.naturalWidth > 0) {
      drawTrimmedItemPreview(image);
    }

    window.setTimeout(next, 0);
  };

  window.setTimeout(next, 0);
};

const queueItemPreview = (image: HTMLImageElement) => {
  if (processedItemImages.has(image) || queuedItemImages.has(image)) return;
  queuedItemImages.add(image);

  const enqueue = () => {
    if (processedItemImages.has(image)) return;
    itemPreviewQueue.push(image);
    runItemPreviewQueue();
  };

  if (image.complete) {
    if (image.naturalWidth > 0) enqueue();
    return;
  }

  image.addEventListener('load', enqueue, { once: true });
};

const scanItemPreviews = (root: ParentNode) => {
  if (root instanceof HTMLImageElement && root.classList.contains('catalog-card-image')) {
    queueItemPreview(root);
  }

  for (const image of Array.from(root.querySelectorAll<HTMLImageElement>('img.catalog-card-image'))) {
    queueItemPreview(image);
  }
};

scanItemPreviews(document);

const itemPreviewObserver = new MutationObserver(records => {
  for (const record of records) {
    for (const node of Array.from(record.addedNodes)) {
      if (node instanceof HTMLElement) scanItemPreviews(node);
    }
  }
});

itemPreviewObserver.observe(document.body, { childList: true, subtree: true });
console.log('WADDLE_COMMAND_CENTER_ITEM_PREVIEW=READY mode=alpha-trim canonical-pngs=true');

// Keep all browser declarations inside an IIFE. commands-static.js is a classic
// script and already owns top-level lexical names; leaking another `const
// commandsApi` here caused the previous pager enhancement to abort before it
// could render any controls in Chromium 85.
(() => {
  type PagedItemEntry = {
    id: number;
    name: string;
    type: number;
    cost?: number;
    member?: boolean;
  };

  type PagedItemResult = {
    items: PagedItemEntry[];
    total: number;
    page: number;
    pageSize: number;
    pageCount: number;
  };

  const itemTypes: Array<[number, string, string]> = [
    [0, 'All', 'All'],
    [1, 'Colors', 'Color'],
    [2, 'Head', 'Head'],
    [3, 'Face', 'Face'],
    [4, 'Neck', 'Neck'],
    [5, 'Body', 'Body'],
    [6, 'Hand', 'Hand'],
    [7, 'Feet', 'Feet'],
    [8, 'Pins', 'Pin'],
    [9, 'Backgrounds', 'Background'],
    [10, 'Awards', 'Award']
  ];

  const typeName = (type: number) => {
    const match = itemTypes.find(entry => entry[0] === type);
    return match ? match[2] : `Type ${type}`;
  };

  const wrap = document.getElementById('catalog-search-wrap');
  const label = document.getElementById('catalog-label');
  const resultsElement = document.getElementById('catalog-results');
  const searchElement = document.getElementById('catalog-search') as HTMLInputElement | null;
  const statusElement = document.getElementById('command-status');
  const applyButton = document.getElementById('command-button') as HTMLButtonElement | null;
  const api = (window as any).api;

  if (wrap === null || label === null || resultsElement === null || searchElement === null || !api || typeof api.browseItemCatalog !== 'function') {
    console.warn('WADDLE_COMMAND_CENTER_ITEM_BROWSER=WARN reason=required_surface_unavailable');
    return;
  }

  let page = 0;
  let selectedType = 0;
  let pageCount = 1;
  let renderSequence = 0;
  let searchTimer: number | null = null;
  const pageSize = 24;

  const toolbar = document.createElement('div');
  toolbar.className = 'item-browser-toolbar hidden';
  toolbar.setAttribute('aria-label', 'Clothing gallery controls');

  const filters = document.createElement('div');
  filters.className = 'item-type-filters';
  filters.setAttribute('role', 'tablist');
  filters.setAttribute('aria-label', 'Item type');

  const filterButtons = new Map<number, HTMLButtonElement>();
  for (const [value, text] of itemTypes) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'item-type-chip';
    button.dataset.itemType = String(value);
    button.textContent = text;
    button.title = value === 0 ? 'Show all item types' : `Show ${text.toLowerCase()} only`;
    button.setAttribute('role', 'tab');
    button.addEventListener('click', () => {
      if (selectedType === value) return;
      selectedType = value;
      page = 0;
      updateControls();
      void renderGallery(0);
    });
    filterButtons.set(value, button);
    filters.appendChild(button);
  }

  const pager = document.createElement('div');
  pager.className = 'item-browser-pager';

  const summary = document.createElement('span');
  summary.className = 'item-browser-summary';
  summary.textContent = 'Loading…';

  const pageControls = document.createElement('div');
  pageControls.className = 'item-browser-page-controls';

  const makePageButton = (text: string, title: string, action: () => void) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'item-page-button';
    button.textContent = text;
    button.title = title;
    button.addEventListener('click', action);
    pageControls.appendChild(button);
    return button;
  };

  const firstButton = makePageButton('«', 'First page', () => {
    page = 0;
    void renderGallery(0);
  });
  const previousButton = makePageButton('‹', 'Previous page', () => {
    page = Math.max(0, page - 1);
    void renderGallery(page);
  });

  const pageInfo = document.createElement('span');
  pageInfo.className = 'item-page-indicator';
  pageInfo.textContent = '1 / 1';
  pageControls.appendChild(pageInfo);

  const nextButton = makePageButton('›', 'Next page', () => {
    page = Math.min(pageCount - 1, page + 1);
    void renderGallery(page);
  });
  const lastButton = makePageButton('»', 'Last page', () => {
    page = Math.max(0, pageCount - 1);
    void renderGallery(page);
  });

  pager.append(summary, pageControls);
  toolbar.append(filters, pager);
  wrap.insertBefore(toolbar, resultsElement);

  const galleryIsActive = () => {
    return !wrap.classList.contains('hidden') && (label.textContent || '').toLowerCase().includes('clothing gallery');
  };

  const clearResults = () => {
    while (resultsElement.firstChild !== null) resultsElement.removeChild(resultsElement.firstChild);
  };

  const updateControls = (total = 0) => {
    for (const [value, button] of Array.from(filterButtons.entries())) {
      const active = value === selectedType;
      button.classList.toggle('active', active);
      button.setAttribute('aria-selected', active ? 'true' : 'false');
    }

    const atFirst = page <= 0;
    const atLast = page >= pageCount - 1;
    firstButton.disabled = atFirst;
    previousButton.disabled = atFirst;
    nextButton.disabled = atLast;
    lastButton.disabled = atLast;
    pageInfo.textContent = `${page + 1} / ${pageCount}`;
    const start = total === 0 ? 0 : page * pageSize + 1;
    const end = total === 0 ? 0 : Math.min((page + 1) * pageSize, total);
    summary.textContent = total === 0 ? '0 items' : `${start}-${end} of ${total}`;
  };

  const createCard = (entry: PagedItemEntry) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'catalog-result catalog-card';
    button.dataset.catalogId = String(entry.id);
    button.title = `${entry.name} · ${typeName(entry.type)} · ID ${entry.id}`;

    const picture = document.createElement('span');
    picture.className = 'catalog-card-picture';

    const fallback = document.createElement('span');
    fallback.className = 'catalog-card-fallback';
    fallback.textContent = String(entry.id);

    const image = document.createElement('img');
    image.className = 'catalog-card-image';
    image.alt = entry.name;
    image.loading = 'lazy';
    image.decoding = 'async';
    image.src = `../../../../media/default/iconspng/${encodeURIComponent(String(entry.id))}.png`;
    image.addEventListener('load', () => picture.classList.add('image-ready'));
    image.addEventListener('error', () => {
      image.remove();
      picture.classList.add('image-missing');
    });
    picture.append(fallback, image);

    const copy = document.createElement('span');
    copy.className = 'catalog-card-copy';

    const name = document.createElement('span');
    name.className = 'catalog-card-name';
    name.textContent = entry.name;

    const meta = document.createElement('small');
    meta.className = 'catalog-card-meta';
    const cost = typeof entry.cost === 'number' ? ` · ${entry.cost}c` : '';
    const member = entry.member ? ' · M' : '';
    meta.textContent = `#${entry.id} · ${typeName(entry.type)}${cost}${member}`;

    copy.append(name, meta);
    button.append(picture, copy);

    const currentArgument = document.querySelector<HTMLInputElement>('#argument-fields input');
    if (currentArgument !== null && currentArgument.value.trim() === String(entry.id)) button.classList.add('selected');

    button.addEventListener('click', () => {
      const argument = document.querySelector<HTMLInputElement>('#argument-fields input');
      if (argument === null) return;
      argument.value = String(entry.id);
      argument.dispatchEvent(new Event('input', { bubbles: true }));

      for (const card of Array.from(resultsElement.querySelectorAll<HTMLElement>('.catalog-card.selected'))) {
        card.classList.remove('selected');
      }
      button.classList.add('selected');

      if (statusElement !== null) {
        statusElement.textContent = `Selected ${entry.name} (#${entry.id})`;
        statusElement.classList.remove('success', 'error');
        statusElement.classList.add('neutral');
      }
      if (applyButton !== null) applyButton.focus();
    });

    return button;
  };

  async function renderGallery(requestedPage = page) {
    if (!galleryIsActive()) {
      toolbar.classList.add('hidden');
      renderSequence += 1;
      return;
    }

    toolbar.classList.remove('hidden');
    const sequence = ++renderSequence;
    const query = searchElement.value.trim();
    pageInfo.textContent = '…';

    try {
      const result = await Promise.resolve(api.browseItemCatalog({
        query,
        type: selectedType,
        page: requestedPage,
        pageSize
      })) as PagedItemResult;

      if (sequence !== renderSequence || !galleryIsActive()) return;
      page = Math.max(0, Number(result.page) || 0);
      pageCount = Math.max(1, Number(result.pageCount) || 1);
      clearResults();
      resultsElement.classList.add('visual-item-grid');

      if (!Array.isArray(result.items) || result.items.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'history-empty catalog-empty';
        empty.textContent = 'No clothing items match this search/filter.';
        resultsElement.appendChild(empty);
      } else {
        for (const entry of result.items) resultsElement.appendChild(createCard(entry));
      }

      resultsElement.scrollTop = 0;
      updateControls(Math.max(0, Number(result.total) || 0));
      console.log(`WADDLE_COMMAND_CENTER_ITEM_BROWSER=PASS page=${page + 1}/${pageCount} total=${result.total} type=${selectedType} query=${JSON.stringify(query)}`);
    } catch (error) {
      console.error(`WADDLE_COMMAND_CENTER_ITEM_BROWSER=FAIL error=${error instanceof Error ? error.message : String(error)}`);
    }
  }

  const scheduleSearch = (delay = 220) => {
    if (searchTimer !== null) window.clearTimeout(searchTimer);
    searchTimer = window.setTimeout(() => {
      searchTimer = null;
      page = 0;
      void renderGallery(0);
    }, delay);
  };

  searchElement.addEventListener('input', () => scheduleSearch());

  const activationObserver = new MutationObserver(() => {
    if (galleryIsActive()) {
      toolbar.classList.remove('hidden');
      page = 0;
      window.setTimeout(() => void renderGallery(0), 80);
    } else {
      toolbar.classList.add('hidden');
      renderSequence += 1;
    }
  });
  activationObserver.observe(wrap, { attributes: true, attributeFilter: ['class'] });
  activationObserver.observe(label, { childList: true, characterData: true, subtree: true });

  if (galleryIsActive()) {
    toolbar.classList.remove('hidden');
    void renderGallery(0);
  }

  console.log('WADDLE_COMMAND_CENTER_ITEM_BROWSER=READY page_size=24 filters=chips pager=first-prev-next-last isolated_scope=true');
})();
