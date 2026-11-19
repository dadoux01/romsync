<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '../lib/api';
  import { isNewer } from '../lib/version';
  import { t } from '../lib/i18n/index.svelte';

  // A discreet notice for the administrator when a newer release exists.
  // The server does not update itself: the image is updated by its owner
  // (docker compose pull, Dockge…). Hidden per version once dismissed.
  let latest = $state<{ version: string; url: string } | null>(null);
  let current = $state('');
  const key = (v: string) => `romsync-update-dismissed-${v}`;

  onMount(async () => {
    try {
      const u = await api.updates();
      if (!isNewer(u.latest.version, u.server_version)) return;
      try {
        if (localStorage.getItem(key(u.latest.version))) return;
      } catch {
        /* storage unavailable: show it */
      }
      current = u.server_version;
      latest = u.latest;
    } catch {
      /* relay disabled or no release known: nothing to show */
    }
  });

  function dismiss() {
    try {
      if (latest) localStorage.setItem(key(latest.version), '1');
    } catch {
      /* ignore */
    }
    latest = null;
  }
</script>

{#if latest}
  <p class="notice small row update-banner">
    <span>
      {t('update.available', { latest: latest.version, current })}
      <a href={latest.url} target="_blank" rel="noopener noreferrer">{t('update.notes')}</a>
    </span>
    <button class="link small" onclick={dismiss}>{t('update.hide')}</button>
  </p>
{/if}

<style>
  .update-banner {
    justify-content: space-between;
    margin-bottom: 1rem;
  }
</style>
