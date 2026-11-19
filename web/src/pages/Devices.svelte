<script lang="ts">
  import { onDestroy } from 'svelte';
  import { api, type Device } from '../lib/api';
  import { formatDate, relativeDate } from '../lib/format';
  import { t } from '../lib/i18n/index.svelte';

  let devices = $state<Device[] | null>(null);
  let error = $state('');
  let pair = $state<{ code: string; expires: number } | null>(null);
  let now = $state(Date.now());
  const timer = setInterval(() => (now = Date.now()), 1000);
  onDestroy(() => clearInterval(timer));

  const remaining = $derived(pair ? Math.max(0, Math.round((pair.expires - now) / 1000)) : 0);
  const PLATFORMS: Record<string, string> = {
    linux: 'Linux',
    macos: 'macOS',
    windows: 'Windows',
    android: 'Android',
    '3ds': '3DS',
  };

  async function load() {
    try {
      devices = await api.devices();
    } catch (err) {
      error = (err as Error).message;
    }
  }
  $effect(() => {
    load();
  });

  // Refresh the list while a code is valid, to show the new device. The
  // effect depends on this boolean only, not on the countdown.
  const pairing = $derived(remaining > 0);
  $effect(() => {
    if (!pairing) return;
    const t = setInterval(load, 3000);
    return () => clearInterval(t);
  });

  async function newCode() {
    error = '';
    try {
      const res = await api.createPairCode();
      pair = { code: res.code, expires: new Date(res.expires_at).getTime() };
    } catch (err) {
      error = (err as Error).message;
    }
  }

  async function revoke(d: Device) {
    if (!confirm(t('devices.confirmRevoke', { name: d.name }))) return;
    try {
      await api.revokeDevice(d.id);
      await load();
    } catch (err) {
      error = (err as Error).message;
    }
  }
</script>

<div class="spread">
  <h1>{t('devices.title')}</h1>
  <button class="primary" onclick={newCode}>{t('devices.add')}</button>
</div>

{#if pair}
  <div class="card stack pair">
    {#if remaining > 0}
      <p>{t('devices.pairHelp')}</p>
      <p class="code mono">{pair.code}</p>
      <p class="muted">
        {t('devices.server')} <code>{location.origin}</code> ·
        {t('devices.expiresIn', { time: `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, '0')}` })}
      </p>
    {:else}
      <p class="muted">{t('devices.expired')}</p>
    {/if}
    <div><button onclick={() => (pair = null)}>{t('common.close')}</button></div>
  </div>
{/if}

{#if error}<p class="error">{error}</p>{/if}

{#if devices && devices.length === 0}
  <p class="muted">{t('devices.none')}</p>
{:else if devices}
  <div class="card table-wrap">
    <table class="responsive">
      <thead><tr><th>{t('devices.col.name')}</th><th>{t('devices.col.platform')}</th><th>{t('devices.col.seen')}</th><th>{t('devices.col.paired')}</th><th></th></tr></thead>
      <tbody>
        {#each devices as d (d.id)}
          <tr class:revoked={d.revoked_at}>
            <td>
              <strong>{d.name}</strong>
              {#if d.revoked_at}<span class="badge danger">{t('devices.revoked')}</span>{/if}
              {#if d.clock_skew_at && !d.revoked_at}
                <div class="notice small">
                  {t('devices.clockSkew', { date: formatDate(d.clock_skew_at) })}
                </div>
              {/if}
            </td>
            <td>{PLATFORMS[d.platform] ?? (d.platform === 'other' ? t('platform.other') : d.platform)}</td>
            <td title={formatDate(d.last_seen_at)}>{relativeDate(d.last_seen_at)}</td>
            <td>{formatDate(d.created_at)}</td>
            <td>{#if !d.revoked_at}<button class="danger" onclick={() => revoke(d)}>{t('devices.revoke')}</button>{/if}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}

<style>
  .code {
    font-size: 2.2rem;
    font-weight: 700;
    letter-spacing: 0.15em;
    margin: 0;
  }
  .pair {
    margin-bottom: 1rem;
  }
  .revoked td {
    opacity: 0.6;
  }
</style>
