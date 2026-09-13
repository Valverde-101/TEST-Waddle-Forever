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
    const sourceContext = source.getContext('2d', { willReadFrequently: true } as any);
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

    const previewContext = preview.getContext('2d');
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
