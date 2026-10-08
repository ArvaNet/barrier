// On-device storage. The whole app state is one JSON record; photos are blobs.
// The service worker writes notification "Done" taps into `inbox`.

import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import type { AppState } from './types';

export interface InboxItem {
  id?: number;
  date: string;
  slot: 'am' | 'pm';
  status: 'done';
  at: number;
}

interface BarrierDB extends DBSchema {
  kv: { key: string; value: unknown };
  photos: { key: string; value: Blob };
  thumbs: { key: string; value: Blob };
  inbox: { key: number; value: InboxItem };
}

let dbp: Promise<IDBPDatabase<BarrierDB>> | null = null;

export function db() {
  if (!dbp) {
    dbp = openDB<BarrierDB>('barrier', 1, {
      upgrade(d) {
        d.createObjectStore('kv');
        d.createObjectStore('photos');
        d.createObjectStore('thumbs');
        d.createObjectStore('inbox', { keyPath: 'id', autoIncrement: true });
      },
    });
  }
  return dbp;
}

export async function loadState(): Promise<AppState | undefined> {
  return (await (await db()).get('kv', 'state')) as AppState | undefined;
}

export async function saveState(s: AppState): Promise<void> {
  await (await db()).put('kv', s, 'state');
}

export async function putPhoto(id: string, full: Blob, thumb: Blob): Promise<void> {
  const d = await db();
  const tx = d.transaction(['photos', 'thumbs'], 'readwrite');
  await Promise.all([tx.objectStore('photos').put(full, id), tx.objectStore('thumbs').put(thumb, id), tx.done]);
}

export async function getPhoto(id: string, thumb = false): Promise<Blob | undefined> {
  return (await db()).get(thumb ? 'thumbs' : 'photos', id);
}

export async function deletePhoto(id: string): Promise<void> {
  const d = await db();
  const tx = d.transaction(['photos', 'thumbs'], 'readwrite');
  await Promise.all([tx.objectStore('photos').delete(id), tx.objectStore('thumbs').delete(id), tx.done]);
}

export async function allPhotoIds(): Promise<string[]> {
  return (await (await db()).getAllKeys('photos')) as string[];
}

export async function drainInbox(): Promise<InboxItem[]> {
  const d = await db();
  const tx = d.transaction('inbox', 'readwrite');
  const items = await tx.store.getAll();
  await tx.store.clear();
  await tx.done;
  return items;
}

export async function clearAll(): Promise<void> {
  const d = await db();
  const tx = d.transaction(['kv', 'photos', 'thumbs', 'inbox'], 'readwrite');
  await Promise.all([
    tx.objectStore('kv').clear(), tx.objectStore('photos').clear(), tx.objectStore('thumbs').clear(), tx.objectStore('inbox').clear(), tx.done,
  ]);
}

export async function requestPersistence(): Promise<boolean> {
  try {
    if (navigator.storage?.persisted && (await navigator.storage.persisted())) return true;
    return (await navigator.storage?.persist?.()) ?? false;
  } catch {
    return false;
  }
}
