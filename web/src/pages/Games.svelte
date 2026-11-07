<script lang="ts">
  import { api, type Game } from '../lib/api';
  import { formatSize, relativeDate } from '../lib/format';
  import { REGIONS } from '../lib/saves';

  let games = $state<Game[] | null>(null);
  let error = $state('');
  let filter = $state('');

  const shown = $derived(
    (games ?? []).filter(
      (g) => !filter || g.title.toLowerCase().includes(filter.toLowerCase()) || g.code.toLowerCase().includes(filter.toLowerCase()),
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
  <h1>Jeux</h1>
  <div class="row">
    {#if games && games.length > 6}
      <input type="search" placeholder="Filtrer…" bind:value={filter} aria-label="Filtrer les jeux" />
    {/if}
    <a class="button primary" href="/import">Importer une save</a>
  </div>
</div>

{#if error}
  <p class="error">{error}</p>
{:else if !games}
  <p class="muted">Chargement…</p>
{:else if games.length === 0}
  <div class="card stack">
    <p>Aucune save pour l’instant.</p>
    <p class="muted">
      Appaire un appareil depuis la page <a href="/devices">Appareils</a>, ou importe un fichier <code>.sav</code> /
      <code>.dsv</code> depuis la page <a href="/import">Importer</a>.
    </p>
  </div>
{:else}
  <div class="card table-wrap">
    <table class="responsive">
      <thead>
        <tr><th>Jeu</th><th>Code</th><th>Dernière save</th><th>Appareil</th><th>Versions</th></tr>
      </thead>
      <tbody>
        {#each shown as g (g.code)}
          <tr>
            <td>
              <a href={`/games/${encodeURIComponent(g.code)}`}><strong>{g.title}</strong></a>
              {#if g.conflict}<span class="badge warn" title="La dernière save envoyée divergeait : conflit résolu automatiquement">conflit</span>{/if}
            </td>
            <td class="mono">{g.code}{#if g.region && REGIONS[g.region]} <span class="muted small">({REGIONS[g.region]})</span>{/if}</td>
            <td>{g.active_version ? relativeDate(g.active_version.saved_at) : '—'}</td>
            <td>{g.active_version?.device_name ?? (g.active_version ? 'site web' : '—')}</td>
            <td>{g.version_count} <span class="muted small">· {formatSize(g.chip_size)}</span></td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}
