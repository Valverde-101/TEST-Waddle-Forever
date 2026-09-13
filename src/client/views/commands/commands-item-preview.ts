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

    // These PNGs are exported on a 600x600 transparent stage. Locate only the
    // visible alpha bounds so the actual Club Penguin item fills its card.
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
    // file:// canvas security varies between Chromium builds. If trimming is not
    // permitted, preserve the valid image and use a centered visual zoom rather
    // than hiding it or generating another network request.
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

    // Process one alpha scan per task so opening/searching the gallery does not
    // freeze the small Electron window when many thumbnails arrive together.
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

// ---------------------------------------------------------------------------
// Clothing gallery pagination + canonical Club Penguin equipment-slot filter.
// The central item table owns the item type. SWFs remain visual assets; the UI
// never guesses Head/Face/Body/etc. from filenames or from SWF contents.
// ---------------------------------------------------------------------------
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

const ITEM_TYPES: Array<[number, string]> = [
  [0, 'All'],
  [1, 'Colors'],
  [2, 'Head'],
  [3, 'Face'],
  [4, 'Neck'],
  [5, 'Body'],
  [6, 'Hand'],
  [7, 'Feet'],
  [8, 'Pins'],
  [9, 'Backgrounds'],
  [10, 'Awards']
];

const itemTypeName = (type: number) => {
  const match = ITEM_TYPES.find(entry => entry[0] === type);
  return match ? match[1] : `Type ${type}`;
};

const catalogWrap = document.getElementById('catalog-search-wrap');
const catalogResultsElement = document.getElementById('catalog-results');
const catalogSearchElement = document.getElementById('catalog-search') as HTMLInputElement | null;
const commandStatusElement = document.getElementById('command-status');
const commandButtonElement = document.getElementById('command-button') as HTMLButtonElement | null;
const commandsApi = (window as any).api;

let itemGalleryPage = 0;
let itemGalleryType = 0;
let itemGalleryRenderSequence = 0;
let itemGalleryTimer: number | null = null;
const ITEM_GALLERY_PAGE_SIZE = 24;

const galleryStyle = document.createElement('style');
galleryStyle.textContent = `
  .item-gallery-toolbar{display:flex;align-items:center;gap:4px;margin-top:4px;min-width:0}
  .item-gallery-toolbar.hidden{display:none!important}
  .item-gallery-type{min-width:0;flex:1 1 auto;height:24px!important;min-height:24px!important;max-height:24px!important;padding:2px 5px!important;font-size:7.5px!important}
  .item-gallery-pager{display:flex;align-items:center;gap:2px;flex:0 0 auto}
  .item-gallery-page-button{width:23px;height:23px;min-width:23px;padding:0;border:1px solid #d7e1ec;border-radius:6px;background:#fff;color:#35506c;font-size:10px;font-weight:800;cursor:pointer}
  .item-gallery-page-button:hover:not(:disabled){border-color:#8abce8;background:#f4f9fd}
  .item-gallery-page-button:disabled{opacity:.35;cursor:default}
  .item-gallery-page-info{min-width:51px;color:#60748a;font-size:7px;font-weight:700;text-align:center;white-space:nowrap}
  .catalog-card-type{font-weight:700}
`;
document.head.appendChild(galleryStyle);

const galleryToolbar = document.createElement('div');
galleryToolbar.id = 'item-gallery-toolbar';
galleryToolbar.className = 'item-gallery-toolbar hidden';

const galleryTypeSelect = document.createElement('select');
galleryTypeSelect.className = 'item-gallery-type';
galleryTypeSelect.title = 'Filter by Club Penguin item slot';
for (const [value, label] of ITEM_TYPES) {
  const option = document.createElement('option');
  option.value = String(value);
  option.textContent = label;
  galleryTypeSelect.appendChild(option);
}

const galleryPager = document.createElement('div');
galleryPager.className = 'item-gallery-pager';

const makePageButton = (text: string, title: string) => {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'item-gallery-page-button';
  button.textContent = text;
  button.title = title;
  return button;
};

const firstPageButton = makePageButton('«', 'First page');
const previousPageButton = makePageButton('‹', 'Previous page');
const pageInfo = document.createElement('span');
pageInfo.className = 'item-gallery-page-info';
pageInfo.textContent = '1 / 1';
const nextPageButton = makePageButton('›', 'Next page');
const lastPageButton = makePageButton('»', 'Last page');
galleryPager.append(firstPageButton, previousPageButton, pageInfo, nextPageButton, lastPageButton);
galleryToolbar.append(galleryTypeSelect, galleryPager);

if (catalogWrap !== null && catalogResultsElement !== null) {
  catalogResultsElement.insertAdjacentElement('afterend', galleryToolbar);
}

const clearCatalogResults = () => {
  if (catalogResultsElement === null) return;
  while (catalogResultsElement.firstChild !== null) catalogResultsElement.removeChild(catalogResultsElement.firstChild);
};

const isItemGalleryActive = () => {
  return catalogWrap !== null && !catalogWrap.classList.contains('hidden') && catalogResultsElement !== null && catalogResultsElement.classList.contains('visual-item-grid');
};

const createPagedItemCard = (entry: PagedItemEntry): HTMLButtonElement => {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'catalog-result catalog-card';
  button.dataset.catalogId = String(entry.id);
  button.title = `${entry.name} · ${itemTypeName(entry.type)} · ID ${entry.id}`;

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
  meta.innerHTML = `#${entry.id} · <span class="catalog-card-type">${itemTypeName(entry.type)}</span>${cost}${member}`;

  copy.append(name, meta);
  button.append(picture, copy);

  const currentArgument = document.querySelector<HTMLInputElement>('#argument-fields input');
  if (currentArgument !== null && currentArgument.value.trim() === String(entry.id)) button.classList.add('selected');

  button.addEventListener('click', () => {
    const argument = document.querySelector<HTMLInputElement>('#argument-fields input');
    if (argument === null) return;
    argument.value = String(entry.id);
    argument.dispatchEvent(new Event('input', { bubbles: true }));

    if (catalogResultsElement !== null) {
      for (const card of Array.from(catalogResultsElement.querySelectorAll<HTMLElement>('.catalog-card.selected'))) {
        card.classList.remove('selected');
      }
    }
    button.classList.add('selected');

    if (commandStatusElement !== null) {
      commandStatusElement.textContent = `Selected ${entry.name} (#${entry.id})`;
      commandStatusElement.classList.remove('success', 'error');
      commandStatusElement.classList.add('neutral');
    }
    if (commandButtonElement !== null) commandButtonElement.focus();
  });

  return button;
};

const renderPagedItemGallery = async (requestedPage = itemGalleryPage) => {
  if (!isItemGalleryActive() || catalogResultsElement === null || typeof commandsApi?.browseItemCatalog !== 'function') {
    galleryToolbar.classList.add('hidden');
    return;
  }

  const sequence = ++itemGalleryRenderSequence;
  const query = catalogSearchElement ? catalogSearchElement.value.trim() : '';
  galleryToolbar.classList.remove('hidden');
  pageInfo.textContent = '…';

  try {
    const result = await Promise.resolve(commandsApi.browseItemCatalog({
      query,
      type: itemGalleryType,
      page: requestedPage,
      pageSize: ITEM_GALLERY_PAGE_SIZE
    })) as PagedItemResult;

    if (sequence !== itemGalleryRenderSequence || !isItemGalleryActive()) return;
    itemGalleryPage = result.page;
    clearCatalogResults();

    if (!Array.isArray(result.items) || result.items.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'history-empty catalog-empty';
      empty.textContent = 'No clothing items match this page/filter.';
      catalogResultsElement.appendChild(empty);
    } else {
      for (const entry of result.items) catalogResultsElement.appendChild(createPagedItemCard(entry));
    }

    catalogResultsElement.scrollTop = 0;
    pageInfo.textContent = `${result.page + 1} / ${result.pageCount}`;
    pageInfo.title = `${result.total} matching items · ${result.pageSize} per page`;
    firstPageButton.disabled = result.page <= 0;
    previousPageButton.disabled = result.page <= 0;
    nextPageButton.disabled = result.page >= result.pageCount - 1;
    lastPageButton.disabled = result.page >= result.pageCount - 1;
    lastPageButton.dataset.lastPage = String(Math.max(0, result.pageCount - 1));

    console.log(`WADDLE_COMMAND_CENTER_ITEM_PAGER=PASS page=${result.page + 1}/${result.pageCount} total=${result.total} type=${itemGalleryType} query=${JSON.stringify(query)}`);
  } catch (error) {
    console.error(`WADDLE_COMMAND_CENTER_ITEM_PAGER=FAIL error=${error instanceof Error ? error.message : String(error)}`);
  }
};

const schedulePagedItemGallery = (delay = 190) => {
  if (itemGalleryTimer !== null) window.clearTimeout(itemGalleryTimer);
  itemGalleryTimer = window.setTimeout(() => {
    itemGalleryTimer = null;
    void renderPagedItemGallery(itemGalleryPage);
  }, delay);
};

firstPageButton.addEventListener('click', () => {
  itemGalleryPage = 0;
  void renderPagedItemGallery(0);
});
previousPageButton.addEventListener('click', () => {
  itemGalleryPage = Math.max(0, itemGalleryPage - 1);
  void renderPagedItemGallery(itemGalleryPage);
});
nextPageButton.addEventListener('click', () => {
  itemGalleryPage += 1;
  void renderPagedItemGallery(itemGalleryPage);
});
lastPageButton.addEventListener('click', () => {
  const last = Number(lastPageButton.dataset.lastPage || '0');
  itemGalleryPage = Number.isFinite(last) ? Math.max(0, last) : 0;
  void renderPagedItemGallery(itemGalleryPage);
});
galleryTypeSelect.addEventListener('change', () => {
  itemGalleryType = Number(galleryTypeSelect.value) || 0;
  itemGalleryPage = 0;
  void renderPagedItemGallery(0);
});

if (catalogSearchElement !== null) {
  catalogSearchElement.addEventListener('input', () => {
    itemGalleryPage = 0;
    schedulePagedItemGallery(190);
  });
}

if (catalogResultsElement !== null) {
  const galleryModeObserver = new MutationObserver(() => {
    if (isItemGalleryActive()) {
      itemGalleryPage = 0;
      schedulePagedItemGallery(190);
    } else {
      galleryToolbar.classList.add('hidden');
      itemGalleryRenderSequence += 1;
    }
  });
  galleryModeObserver.observe(catalogResultsElement, { attributes: true, attributeFilter: ['class'] });
}

if (catalogWrap !== null) {
  const catalogVisibilityObserver = new MutationObserver(() => {
    if (isItemGalleryActive()) schedulePagedItemGallery(190);
    else galleryToolbar.classList.add('hidden');
  });
  catalogVisibilityObserver.observe(catalogWrap, { attributes: true, attributeFilter: ['class'] });
}

if (isItemGalleryActive()) schedulePagedItemGallery(0);
console.log('WADDLE_COMMAND_CENTER_ITEM_PAGER=READY page_size=24 type_filter=canonical-item-table');
