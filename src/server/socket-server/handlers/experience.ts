import fs from "fs";
import path from "path";
import { PenguinHandler } from "./handlers";

/**
 * Persisted Engine 3/vanilla experience flags.
 *
 * These values are protocol state rather than timeline/media state. Keep them
 * outside the legacy PenguinJson schema so old penguin saves remain readable
 * without a database-version migration, while still preserving the values
 * across Waddle restarts and date changes.
 */
type ExperienceState = {
  schema: 'waddle-modern-experience/v1';
  mapCategory: number;
  openedPlayercard: boolean;
  specialWave: boolean;
  specialDance: boolean;
  specialSnowball: boolean;
};

const defaultExperienceState = (): ExperienceState => ({
  schema: 'waddle-modern-experience/v1',
  mapCategory: 0,
  openedPlayercard: false,
  specialWave: false,
  specialDance: false,
  specialSnowball: false
});

const normalizeExperienceState = (value: unknown): ExperienceState => {
  const source = typeof value === 'object' && value !== null
    ? value as Partial<Record<keyof ExperienceState, unknown>>
    : {};
  const category = Number(source.mapCategory);
  return {
    schema: 'waddle-modern-experience/v1',
    mapCategory: Number.isInteger(category) && category >= 0 && category <= 4 ? category : 0,
    openedPlayercard: source.openedPlayercard === true,
    specialWave: source.specialWave === true,
    specialDance: source.specialDance === true,
    specialSnowball: source.specialSnowball === true
  };
};

class ExperienceStateStore {
  private readonly root = path.join(process.cwd(), 'user-data', 'data', 'experience');
  private readonly cache = new Map<number, ExperienceState>();
  private readonly writes = new Map<number, Promise<ExperienceState>>();

  private filePath(penguinId: number) {
    return path.join(this.root, `${penguinId}.json`);
  }

  private async load(penguinId: number): Promise<ExperienceState> {
    const cached = this.cache.get(penguinId);
    if (cached !== undefined) return cached;

    let state = defaultExperienceState();
    try {
      const raw = await fs.promises.readFile(this.filePath(penguinId), 'utf8');
      state = normalizeExperienceState(JSON.parse(raw) as unknown);
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== 'ENOENT') throw error;
    }
    this.cache.set(penguinId, state);
    return state;
  }

  public async get(penguinId: number): Promise<ExperienceState> {
    const pending = this.writes.get(penguinId);
    if (pending !== undefined) return pending;
    return this.load(penguinId);
  }

  public update(
    penguinId: number,
    updater: (state: ExperienceState) => ExperienceState
  ): Promise<ExperienceState> {
    const previous = this.writes.get(penguinId) ?? Promise.resolve(undefined);
    const queued = previous.catch(() => undefined).then(async () => {
      const current = this.cache.get(penguinId) ?? await this.load(penguinId);
      const next = normalizeExperienceState(updater({ ...current }));
      await fs.promises.mkdir(this.root, { recursive: true });
      const target = this.filePath(penguinId);
      const temporary = `${target}.${process.pid}.tmp`;
      await fs.promises.writeFile(temporary, JSON.stringify(next), 'utf8');
      await fs.promises.rename(temporary, target);
      this.cache.set(penguinId, next);
      return next;
    });

    this.writes.set(penguinId, queued);
    void queued.finally(() => {
      if (this.writes.get(penguinId) === queued) this.writes.delete(penguinId);
    }).catch(() => undefined);
    return queued;
  }
}

const experienceState = new ExperienceStateStore();

/** nx#gas — returns dance/wave/snowball capability flags in canonical order. */
export const handleGetActionStatus: PenguinHandler<[]> = async ({ penguin, msg }) => {
  const state = await experienceState.get(penguin.id);
  msg.send(
    penguin,
    'gas',
    state.specialDance ? 1 : 0,
    state.specialWave ? 1 : 0,
    state.specialSnowball ? 1 : 0
  );
};

/** nx#mcs(mapCategory) — persist map category when it is one of 0..4. */
export const handleMapCategorySetting: PenguinHandler<[number]> = async ({ penguin }, mapCategory) => {
  if (!Number.isInteger(mapCategory) || mapCategory < 0 || mapCategory > 4) return;
  await experienceState.update(penguin.id, state => ({ ...state, mapCategory }));
};

/** nx#pcos — remember that the modern playercard has been opened. */
export const handlePlayercardOpenedSetting: PenguinHandler<[]> = async ({ penguin }) => {
  await experienceState.update(penguin.id, state => ({ ...state, openedPlayercard: true }));
};

/** nx#swave — unlock/record special wave. */
export const handleSpecialWave: PenguinHandler<[]> = async ({ penguin }) => {
  await experienceState.update(penguin.id, state => ({ ...state, specialWave: true }));
};

/** nx#sdance — unlock/record special dance. */
export const handleSpecialDance: PenguinHandler<[]> = async ({ penguin }) => {
  await experienceState.update(penguin.id, state => ({ ...state, specialDance: true }));
};

/** nx#ssnowball — unlock/record special snowball. */
export const handleSpecialSnowball: PenguinHandler<[]> = async ({ penguin }) => {
  await experienceState.update(penguin.id, state => ({ ...state, specialSnowball: true }));
};
