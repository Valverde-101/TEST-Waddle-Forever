import fs from 'fs'
import unzipper from 'unzipper';
import { showProgress, ProgressCallback } from './views/progress/progress';

function unzipFile(zipDir: string, outDir: string, progress: ProgressCallback, end: () => void, onError: (err: unknown) => void) {
  let settled = false;

  const unlink = () => {
    try {
      if (fs.existsSync(zipDir)) {
        fs.unlinkSync(zipDir);
      }
    } catch (error) {
      // Cleanup failure should not hide the original extraction result.
      console.warn(`Could not remove temporary archive ${zipDir}:`, error);
    }
  }

  const succeed = () => {
    if (settled) {
      return;
    }
    settled = true;
    unlink();
    end();
  };

  const handleError = (err: unknown) => {
    if (settled) {
      return;
    }
    settled = true;
    unlink();
    end();
    onError(err);
  }

  try {
    const stream = fs.createReadStream(zipDir)
    const unzipStream = unzipper.Extract({ path: outDir })
    const totalBytes = fs.statSync(zipDir).size;
    let processedBytes = 0

    unzipStream.once('close', succeed)
    unzipStream.once('error', handleError)

    stream.on('data', (chunk) => {
      processedBytes += chunk.length;
      if (totalBytes > 0) {
        progress(processedBytes / totalBytes);
      }
    })

    stream.once('error', handleError);
    stream.pipe(unzipStream)
  } catch (error) {
    handleError(error);
  }
}

export async function unzip(zipDir: string, outDir: string) {
  await showProgress('Extracting file', async (progress, end) => {
    return await new Promise<boolean>((resolve, reject) => {
      unzipFile(zipDir, outDir, progress, () => {
        end();
        resolve(true);
      }, (err) => {
        reject(err);
      })
    })
  })
}
