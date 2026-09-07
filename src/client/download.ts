import fs from 'fs';
import http from 'http';
import https from 'https';

import { logError, parseURL } from '@common/utils';
import { showProgress } from './views/progress/progress';

const removePartialFile = (destination: string) => {
  fs.unlink(destination, () => {});
};

async function downloadFile(
  url: string,
  destination: string,
  update: (progress: number) => void,
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
      if (settled) {
        return;
      }
      settled = true;
      if (file && !file.destroyed) {
        file.destroy();
      }
      if (destinationTouched) {
        removePartialFile(destination);
      }
      logError('Error downloading', error);
      finish();
      reject(error);
    };

    const request = module.get(url, (response) => {
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

      response.on('data', (chunk) => {
        downloadedSize += chunk.length;
        if (totalSize > 0) {
          update(downloadedSize / totalSize);
        }
      });

      response.once('aborted', () => {
        fail(new Error(`Download aborted before completion: ${url}`));
      });
      response.once('error', error => {
        fail(error);
      });
      file.once('error', error => {
        fail(error);
      });
      file.once('finish', () => {
        if (settled) {
          return;
        }
        settled = true;
        file?.close();
        finish();
        resolve(true);
      });

      response.pipe(file);
    });

    request.once('error', error => {
      fail(error);
    });
  });
}

interface ProgressObject {
  current: number,
  total: number
}

export async function download(url: string, destination: string, progress?: ProgressObject): Promise<boolean> {
  let message = 'Downloading files'
  if (progress !== undefined) {
    message += ` (${progress.current} out of ${progress.total})`
  }
  message += ': '
  
  return await showProgress(message, async (progressCallback, end) => {
    return await downloadFile(url, destination, progressCallback, end)
  })
}
