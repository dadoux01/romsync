<script lang="ts">
  import { api, type Game } from '../lib/api';
  import { formatSize, relativeDate } from '../lib/format';
  import { regionName, type GameSystem } from '../lib/saves';
  import { t } from '../lib/i18n/index.svelte';

  let games = $state<Game[] | null>(null);
  let error = $state('');
  let filter = $state('');
  let system = $state<GameSystem | ''>('');

  // Consoles present in the list: the filter only shows with more than one.
  const systems = $derived([...new Set((games ?? []).map((g) => g.system))]);
  const shown = $derived(
    (games ?? []).filter(
      (g) =>
        (!system || g.system === system) &&
        (!filter || g.title.toLowerCase().includes(filter.toLowerCase()) || g.code.toLowerCase().includes(filter.toLowerCase())),
    ),
  );

  $effect(() => {
    api.games().then(
      (g) => (games = g),
      (err) => (error = err.message),
    );
  });
</script>

<div class="spread">
  <h1>{t('games.title')}</h1>
  <div class="row">
    {#if systems.length > 1}
      <select bind:value={system} aria-label={t('system.label')}>
        <option value="">{t('system.all')}</option>
        {#each systems as s (s)}<option value={s}>{t(`system.${s}`)}</option>{/each}
      </select>
    {/if}
    {#if games && games.length > 6}
      <input type="search" placeholder={t('games.filter')} bind:value={filter} aria-label={t('games.filterLabel')} />
    {/if}
    <a class="button primary" href="/import">{t('games.import')}</a>
  </div>
</div>

{#if error}
  <p class="error">{error}</p>
{:else if !games}
  <p class="muted">{t('common.loading')}</p>
{:else if games.length === 0}
  <div class="card stack">
    <p>{t('games.empty')}</p>
    <p class="muted">{@html t('games.empty.html')}</p>
  </div>
{:else}
  <div class="card table-wrap">
    <table class="responsive">
      <thead>
        <tr><th>{t('games.col.game')}</th><th>{t('system.label')}</th><th>{t('games.col.code')}</th><th>{t('games.col.lastSave')}</th><th>{t('games.col.device')}</th><th>{t('games.col.versions')}</th></tr>
      </thead>
      <tbody>
        {#each shown as g (g.code)}
          <tr>
            <td>
              <a href={`/games/${encodeURIComponent(g.code)}`}><strong>{g.title}</strong></a>
              {#if g.conflict}<span class="badge warn" title={t('games.conflict.title')}>{t('games.conflict')}</span>{/if}
            </td>
            <td>{t(`system.${g.system}`)}</td>
            <td class="mono">{g.code}{#if regionName(g.region)} <span class="muted small">({regionName(g.region)})</span>{/if}</td>
            <td>{g.active_version ? relativeDate(g.active_version.saved_at) : '—'}</td>
            <td>{g.active_version?.device_name ?? (g.active_version ? t('common.website') : '—')}</td>
            <td>{g.version_count} <span class="muted small">· {formatSize(g.chip_size)}</span></td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}
