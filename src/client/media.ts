import path from 'path'
import fs from 'fs'

import electronIsDev from "electron-is-dev";

import { VERSION } from '@common/version';
import settingsManager from '@server/settings';
import { download } from './download';
import { unzip } from './unzip';
import { logError, MEDIA_DIRECTORY, postJSON } from '@common/utils';

/**
 * Downloads and extracts a media folder from the website.
 * @returns true only when the complete download, extraction and version marker succeeded.
 */
export const downloadMediaFolder = async (
  mediaName: string,
  onSuccess: () => void,
  onFail: (err: unknown) => void
): Promise<boolean> => {
  // in dev, the medias are always installed
  // can only test this in production builds
  if (electronIsDev) {
    onSuccess();
    return true;
  }

  // remove any existing .zip files that may be leftover if a download was cancelled
  try {
    // media folder should exist by this point
    for (const file of fs.readdirSync(MEDIA_DIRECTORY).filter(f => f.endsWith('.zip'))) {
      try {
        fs.unlinkSync(path.join(MEDIA_DIRECTORY, file));
      } catch (err) {
        logError('Failed to unlink existing zip file', err);
      }
    }
  } catch (err) {
    logError('Error reading media directory for zip files', err);
  }

  // use date to avoid collision (unlink only deletes after the app is closed)
  const zipName = String(Date.now()) + '.zip';
  const zipDir = path.join(MEDIA_DIRECTORY, zipName);
  const folderDestination = path.join(MEDIA_DIRECTORY, mediaName);

  try {
    await download(`https://github.com/nhaar/Waddle-Forever/releases/download/v${VERSION}/${mediaName}.zip`, zipDir);
    await unzip(zipDir, folderDestination);
    fs.writeFileSync(path.join(folderDestination, '.version'), VERSION);
    onSuccess();
    return true;
  } catch (error) {
    logError(`Failed to install media folder ${mediaName}`, error);
    try {
      if (fs.existsSync(zipDir)) {
        fs.unlinkSync(zipDir);
      }
    } catch (cleanupError) {
      logError(`Failed to remove partial media archive ${zipDir}`, cleanupError);
    }
    onFail(error);
    return false;
  }
}

const checkMedia = async (mediaName: string): Promise<boolean> => {
  let isUpToDate = true;

  const TARGET_DIRECTORY = path.join(MEDIA_DIRECTORY, mediaName);
  if (!fs.existsSync(TARGET_DIRECTORY)) {
    isUpToDate = false;
    try {
      fs.mkdirSync(TARGET_DIRECTORY, { recursive: true });
    } catch (_error) {
      throw new AdminError();
    }
  }

  const versionFile = path.join(TARGET_DIRECTORY, '.version');
  if (!fs.existsSync(versionFile)) {
    isUpToDate = false;
  } else {
    const previousVersion = fs.readFileSync(versionFile, { encoding: 'utf-8' }).trim();
    if (previousVersion === VERSION) {
      isUpToDate = true;
    } else {
      // even though the versions are different,
      // the contents may be the same, so we can skip
      // downloading a new file if they are equivalent
      const response = await postJSON('/compare-versions', { oldVersion: previousVersion, newVersion: VERSION, media: mediaName });
      if (response !== undefined) {
        if (response.isEquivalent) {
          fs.writeFileSync(versionFile, VERSION);
          isUpToDate = true;
        } else {
          isUpToDate = false;
        }
      } else {
        // API error on server, we assume there's no equivalence
        // this scenario shouldn't happen, and if it does
        // we might get an error trying to download anyways
        isUpToDate = false;
      }
    }
  }

  if (!isUpToDate) {
    fs.rmSync(TARGET_DIRECTORY, { recursive: true, force: true });
    let failure: unknown;
    const success = await downloadMediaFolder(mediaName, () => {}, (err) => {
      failure = err;
    });

    if (!success) {
      if (failure instanceof Error) {
        throw failure;
      }
      throw new Error(`Could not install required media folder: ${mediaName}`);
    }
  }

  return true;
}

export class AdminError extends Error {
  constructor() {
    super('Could not create media directory');
  }
}

/**
 * Initializes the media folders, downloading when needed to update things
 * @returns Whether the checks and downloads were successful
 */
export const startMedia = async (): Promise<void> => {
  // in dev, there's no reason to mess with the media folder as they are all part of the github repo
  if (electronIsDev) {
    return;
  }

  if (!fs.existsSync(MEDIA_DIRECTORY)) {
    try {
      fs.mkdirSync(MEDIA_DIRECTORY, { recursive: true });
    } catch (_error) {
      throw new AdminError();
    }
  }

  // check media of name "string" if the "boolean" is true
  const mediaConditions: [string, boolean][] = [
    ['default', true], // mandatory check
    ['clothing', settingsManager.settings.clothing]
  ];

  for (const mediaCondition of mediaConditions) {
    const [name, mustCheck] = mediaCondition;
    if (mustCheck) {
      await checkMedia(name);
    }
  }
}
