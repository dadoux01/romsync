import { api, setUnauthorizedHandler, type User } from './api';

export const session = $state<{ user: User | null; ready: boolean; setupNeeded: boolean }>({
  user: null,
  ready: false,
  setupNeeded: false,
});

setUnauthorizedHandler(() => {
  session.user = null;
});

export async function loadSession() {
  try {
    session.setupNeeded = await api.setupNeeded();
    if (!session.setupNeeded) {
      try {
        session.user = await api.me();
      } catch {
        session.user = null;
      }
    }
  } finally {
    session.ready = true;
  }
}
