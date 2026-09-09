import path from 'path';
import fs from 'fs';
import http from 'http';
import https from 'https';
import unzipper from 'unzipper';

import electronIsDev from 'electron-is-dev';
import { BrowserWindow, dialog } from 'electron';

import { VERSION } from '@common/constants';
import settingsManager from '@server/settings';
import { logError, MEDIA_DIRECTORY, parseURL, postJSON } from '@common/utils';
import { createProgressBarWindow, ProgressCallback, setPrompt, showProgress } from './views/progress/progress';

let progressWin: BrowserWindow | null = null;

/** Creates the shared setup/progress window if needed and reuses it across media phases. */
export async function progressWindow(): Promise<BrowserWindow> {
  if (progressWin === null || progressWin.isDestroyed()) {
    progressWin = await createProgressBarWindow();
  }
  return progressWin;
}

export function destroyProgressWindow(): void {
  if (progressWin !== null && !progressWin.isDestroyed()) {
    // destroy, not close, otherwise the close-confirmation handler is triggered.
    progressWin.destroy();
  }
  progressWin = null;
}

const removePartialFile = (destination: string) => {
  fs.unlink(destination, () => {});
};

async function downloadFile(
  url: string,
  destination: string,
  update: ProgressCallback,
  finish: () => void,
  maxRedirects = 5
): Promise<boolean> {
  const { protocol } = parseURL(url);
  const module = protocol === 'http' ? http : https;

  return await new Promise<boolean>((resolve, reject) => {
    let settled = false;
    let destinationTouched = false;
    let file: fs.WriteStream | undefined;

    const fail = (error: Error) => {
      if (settled) return;
      settled = true;
      if (file && !file.destroyed) file.destroy();
      if (destinationTouched) removePartialFile(destination);
      logError('Error downloading', error);
      finish();
      reject(error);
    };

    const request = module.get(url, response => {
      const status = response.statusCode ?? 0;

      if ([301, 302, 303, 307, 308].includes(status)) {
        const location = response.headers.location;
        response.resume();
        if (location === undefined) {
          fail(new Error(`Redirect from ${url} did not include a Location header`));
          return;
        }
        if (maxRedirects <= 0) {
          fail(new Error(`Too many redirects while downloading ${url}`));
          return;
        }

        let redirectURL: string;
        try {
          redirectURL = new URL(location, url).toString();
        } catch (error) {
          fail(error instanceof Error ? error : new Error(`Invalid redirect URL from ${url}`));
          return;
        }

        settled = true;
        resolve(downloadFile(redirectURL, destination, update, finish, maxRedirects - 1));
        return;
      }

      if (status < 200 || status >= 300) {
        response.resume();
        fail(new Error(`Download failed with HTTP ${status} for ${url}`));
        return;
      }

      destinationTouched = true;
      file = fs.createWriteStream(destination);
      const totalSize = Number(response.headers['content-length'] || 0);
      let downloadedSize = 0;

      response.on('data', chunk => {
        downloadedSize += chunk.length;
        if (totalSize > 0) update(downloadedSize / totalSize);
      });
      response.once('aborted', () => fail(new Error(`Download aborted before completion: ${url}`)));
      response.once('error', fail);
      file.once('error', fail);
      file.once('finish', () => {
        if (settled) return;
        settled = true;
        file?.close();
        finish();
        resolve(true);
      });
      response.pipe(file);
    });

    request.once('error', fail);
  });
}

const downloadMessages: Record<string, string> = {
  default: 'Downloading Media:',
  clothing: 'Downloading Clothing:'
};

async function download(url: string, destination: string, name: string): Promise<boolean> {
  const win = await progressWindow();
  setPrompt(downloadMessages[name] ?? 'Downloading files:', win);
  return await showProgress(win, async (progress, end) => {
    return await downloadFile(url, destination, progress, end);
  });
}

export async function unzip(zipDir: string, outDir: string): Promise<boolean> {
  const win = await progressWindow();
  setPrompt('Extracting Media:', win);

  return await showProgress(win, async (progress, end) => {
    return await new Promise<boolean>((resolve, reject) => {
      let settled = false;

      const unlink = () => {
        try {
          if (fs.existsSync(zipDir)) fs.unlinkSync(zipDir);
        } catch (error) {
          console.warn(`Could not remove temporary archive ${zipDir}:`, error);
        }
      };

      const succeed = () => {
        if (settled) return;
        settled = true;
        unlink();
        end();
        resolve(true);
      };

      const fail = (error: unknown) => {
        if (settled) return;
        settled = true;
        unlink();
        end();
        reject(error);
      };

      try {
        const stream = fs.createReadStream(zipDir);
        const unzipStream = unzipper.Extract({ path: outDir });
        const totalBytes = fs.statSync(zipDir).size;
        let processedBytes = 0;

        unzipStream.once('close', succeed);
        unzipStream.once('error', fail);
        stream.on('data', chunk => {
          processedBytes += chunk.length;
          if (totalBytes > 0) progress(processedBytes / totalBytes);
        });
        stream.once('error', fail);
        stream.pipe(unzipStream);
      } catch (error) {
        fail(error);
      }
    });
  });
}

/** Downloads and extracts a media folder from the release matching VERSION. */
export const downloadMediaFolder = async (
  mediaName: string,
  onSuccess: () => void,
  onFail: (err: unknown) => void
): Promise<boolean> => {
  if (electronIsDev) {
    onSuccess();
    return true;
  }

  await progressWindow();

  try {
    for (const file of fs.readdirSync(MEDIA_DIRECTORY).filter(file => file.endsWith('.zip'))) {
      try {
        fs.unlinkSync(path.join(MEDIA_DIRECTORY, file));
      } catch (error) {
        logError('Failed to unlink existing zip file', error);
      }
    }
  } catch (error) {
    logError('Error reading media directory for zip files', error);
  }

  const zipDir = path.join(MEDIA_DIRECTORY, `${Date.now()}.zip`);
  const folderDestination = path.join(MEDIA_DIRECTORY, mediaName);

  try {
    await download(`https://github.com/nhaar/Waddle-Forever/releases/download/v${VERSION}/${mediaName}.zip`, zipDir, mediaName);
    await unzip(zipDir, folderDestination);
    fs.writeFileSync(path.join(folderDestination, '.version'), VERSION);
    onSuccess();
    return true;
  } catch (error) {
    logError(`Failed to install media folder ${mediaName}`, error);
    try {
      if (fs.existsSync(zipDir)) fs.unlinkSync(zipDir);
    } catch (cleanupError) {
      logError(`Failed to remove partial media archive ${zipDir}`, cleanupError);
    }
    onFail(error);
    return false;
  }
};

const checkMedia = async (mediaName: string): Promise<boolean> => {
  let isUpToDate = true;
  const targetDirectory = path.join(MEDIA_DIRECTORY, mediaName);

  if (!fs.existsSync(targetDirectory)) {
    isUpToDate = false;
    try {
      fs.mkdirSync(targetDirectory, { recursive: true });
    } catch (_error) {
      throw new AdminError();
    }
  }

  const versionFile = path.join(targetDirectory, '.version');
  if (!fs.existsSync(versionFile)) {
    isUpToDate = false;
  } else {
    const previousVersion = fs.readFileSync(versionFile, 'utf-8').trim();
    if (previousVersion === VERSION) {
      isUpToDate = true;
    } else {
      const response = await postJSON('/compare-versions', {
        oldVersion: previousVersion,
        newVersion: VERSION,
        media: mediaName
      });
      if (response?.isEquivalent === true) {
        fs.writeFileSync(versionFile, VERSION);
        isUpToDate = true;
      } else {
        isUpToDate = false;
      }
    }
  }

  if (!isUpToDate) {
    fs.rmSync(targetDirectory, { recursive: true, force: true });
    let failure: unknown;
    const success = await downloadMediaFolder(mediaName, () => {}, error => {
      failure = error;
    });
    if (!success) {
      if (failure instanceof Error) throw failure;
      throw new Error(`Could not install required media folder: ${mediaName}`);
    }
  }

  return true;
};

export class AdminError extends Error {
  constructor() {
    super('Could not create media directory');
  }
}

/** Initializes required media and handles the optional clothing package. */
export const startMedia = async (): Promise<void> => {
  if (electronIsDev) return;

  if (!fs.existsSync(MEDIA_DIRECTORY)) {
    try {
      fs.mkdirSync(MEDIA_DIRECTORY, { recursive: true });
    } catch (_error) {
      throw new AdminError();
    }
  }

  await checkMedia('default');
  if (settingsManager.settings.clothing) {
    await checkMedia('clothing');
  }

  if (!settingsManager.settings.clothing && settingsManager.settings.answered_packages !== VERSION) {
    if (process.env.WADDLE_NONINTERACTIVE === '1') {
      settingsManager.updateSettings({ answered_packages: VERSION });
      return;
    }

    const result = await dialog.showMessageBox(await progressWindow(), {
      buttons: ['Download Clothing (~600 MB)', 'No Thanks'],
      title: 'Download package?',
      message: 'Would you like to download the clothing package? It includes all non essential clothing items from Club Penguin. If you say no, you can always download it later.',
      defaultId: 0,
      cancelId: 1
    });

    if (result.response === 0) {
      const installed = await downloadMediaFolder('clothing', () => {
        settingsManager.updateSettings({ clothing: true });
      }, error => {
        logError('Optional clothing package download failed', error);
      });
      if (installed) settingsManager.updateSettings({ answered_packages: VERSION });
    } else {
      settingsManager.updateSettings({ answered_packages: VERSION });
    }
  }
};
