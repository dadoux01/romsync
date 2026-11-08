<script lang="ts">
  import { api, type Game, type Version } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { describeSizeEvent, formatDate, formatSize, relativeDate, shortHash } from '../lib/format';
  import { REGIONS } from '../lib/saves';
  import RetentionEditor from '../components/RetentionEditor.svelte';

  let { code }: { code: string } = $props();

  let game = $state<Game | null>(null);
  let versions = $state<Version[]>([]);
  let nextBefore = $state<number | null>(null);
  let error = $state('');
  let actionError = $state('');
  let editingTitle = $state(false);
  let title = $state('');

  async function load() {
    error = '';
    try {
      const games = await api.games();
      game = games.find((g) => g.code === code) ?? null;
      if (!game) {
        error = 'Ce jeu n’existe pas dans ton compte.';
        return;
      }
      const page = await api.versions(code);
      versions = page.versions;
      nextBefore = page.next_before;
    } catch (err) {
      error = (err as Error).message;
    }
  }

  $effect(() => {
    load();
  });

  async function more() {
    if (!nextBefore) return;
    const page = await api.versions(code, nextBefore);
    versions = [...versions, ...page.versions];
    nextBefore = page.next_before;
  }

  async function run(fn: () => Promise<unknown>) {
    actionError = '';
    try {
      await fn();
      await load();
    } catch (err) {
      actionError = (err as Error).message;
    }
  }

  function activate(v: Version) {
    if (!confirm(`Restaurer la version du ${formatDate(v.saved_at)} ? Elle deviendra la save active, et les appareils la téléchargeront avant la prochaine partie.`)) return;
    run(() => api.activate(v.id));
  }

  function remove(v: Version) {
    if (!confirm(`Supprimer définitivement la version du ${formatDate(v.saved_at)} ? Elle disparaîtra de l’historique et ne pourra plus être restaurée.`)) return;
    run(() => api.deleteVersion(v.id));
  }

  function editNote(v: Version) {
    const note = prompt('Note pour cette version :', v.note);
    if (note !== null) run(() => api.updateVersion(v.id, { note }));
  }

  async function saveTitle(e: SubmitEvent) {
    e.preventDefault();
    await run(() => api.updateGame(code, { title }));
    editingTitle = false;
  }

  // Where a divergent version started from: the version its device had
  // last synced (base_version_id), to see what happened at a glance.
  function baseLabel(v: Version): string {
    if (v.base_version_id === null) return 'ne partait d’aucune version (premier envoi de cet appareil pour ce jeu)';
    const base = versions.find((x) => x.id === v.base_version_id);
    if (!base) return `partait de la version n° ${v.base_version_id}, absente de l’historique affiché (supprimée ou plus ancienne)`;
    return `partait de la version du ${formatDate(base.saved_at)} (${base.device_name ?? 'site web'})`;
  }

  // "Conflit résolu automatiquement": the latest upload diverged. The other
  // candidate is that upload when it lost, or the most recent other version
  // when it won.
  const conflict = $derived.by(() => {
    if (!game?.conflict || versions.length === 0) return null;
    const latest = versions.reduce((a, b) => (b.uploaded_at > a.uploaded_at || (b.uploaded_at === a.uploaded_at && b.id > a.id) ? b : a));
    if (!latest.conflict) return null;
    const other = latest.is_active ? versions.find((v) => v.id !== latest.id) : latest;
    return { latest, other };
  });
</script>

{#if error}
  <p class="error">{error}</p>
  <p><a href="/">Retour à la liste</a></p>
{:else if !game}
  <p class="muted">Chargement…</p>
{:else}
  <p class="small"><a href="/">← Jeux</a></p>
  <div class="spread">
    {#if editingTitle}
      <form class="row" onsubmit={saveTitle}>
        <input bind:value={title} maxlength="128" required aria-label="Titre" />
        <button class="primary">Renommer</button>
        <button type="button" onclick={() => (editingTitle = false)}>Annuler</button>
      </form>
    {:else}
      <h1>
        {game.title}
        <button class="link small" onclick={() => ((title = game!.title), (editingTitle = true))}>renommer</button>
      </h1>
    {/if}
    <a class="button primary" href={`/import?game=${encodeURIComponent(code)}`}>Importer une save</a>
  </div>
  <p class="muted">
    <span class="mono">{game.code}</span>
    {#if game.region}· {REGIONS[game.region] ?? `région ${game.region}`}{/if}
    · taille de save {formatSize(game.chip_size)} · vu pour la première fois {relativeDate(game.first_seen_at)}
  </p>

  {#if actionError}<p class="error">{actionError}</p>{/if}

  {#if conflict}
    <div class="notice stack">
      <strong>Conflit résolu automatiquement</strong>
      <span>
        La save envoyée le {formatDate(conflict.latest.uploaded_at)}
        {conflict.latest.device_name ? `par ${conflict.latest.device_name}` : 'depuis le site'} ne partait pas de la version active.
        {conflict.latest.is_active ? 'C’est elle qui est active' : 'Elle n’est pas active'} ; l’autre version est conservée dans l’historique.
      </span>
      {#if conflict.other && !conflict.other.is_active}
        <div><button onclick={() => activate(conflict.other!)}>Activer l’autre version ({formatDate(conflict.other.saved_at)})</button></div>
      {/if}
    </div>
  {/if}

  <h2>Historique</h2>
  <div class="card table-wrap">
    <table class="responsive">
      <thead>
        <tr><th>Sauvegardé le</th><th>Origine</th><th>Taille</th><th>État</th><th></th></tr>
      </thead>
      <tbody>
        {#each versions as v (v.id)}
          <tr>
            <td>
              {formatDate(v.saved_at)}
              {#if v.saved_at_reported}
                <span class="badge warn" title={`Date annoncée par l’appareil : ${formatDate(v.saved_at_reported)}`}>horloge corrigée</span>
              {/if}
              {#if v.note}<div class="muted small">{v.note}</div>{/if}
            </td>
            <td>
              {v.device_name ?? 'site web'}
              {#if v.emulator}<div class="muted small">{v.emulator}</div>{/if}
            </td>
            <td>
              {formatSize(v.size)}
              {#if v.size_event}
                <span class="badge warn" title={describeSizeEvent(v.size_event, v.size)}>
                  {v.size_event.type === 'trimmed' ? 'coupée' : v.size_event.type === 'shrunk' ? 'taille réduite' : 'taille forcée'}
                </span>
                <div class="muted small">{describeSizeEvent(v.size_event, v.size)}</div>
              {/if}
              <div class="muted small mono" title={v.sha256}>{shortHash(v.sha256)}</div>
            </td>
            <td>
              <div class="row">
                {#if v.is_active}<span class="badge active">active</span>{/if}
                {#if v.conflict}<span class="badge warn" title="Envoyée sans partir de la version active">divergente</span>{/if}
                {#if v.pinned}<span class="badge">épinglée</span>{/if}
              </div>
              {#if v.conflict}<div class="muted small">{baseLabel(v)}</div>{/if}
            </td>
            <td>
              <div class="row">
                {#if !v.is_active}<button onclick={() => activate(v)}>Restaurer</button>{/if}
                <button onclick={() => run(() => api.updateVersion(v.id, { pinned: !v.pinned }))}>
                  {v.pinned ? 'Désépingler' : 'Épingler'}
                </button>
                <button onclick={() => editNote(v)}>Note</button>
                <a class="button" href={api.exportURL(v.id, 'raw')} download>.sav</a>
                <a class="button" href={api.exportURL(v.id, 'desmume')} download>.dsv</a>
                <a class="button" href={api.exportURL(v.id, 'flashcard')} download title="Complétée avec 0xFF jusqu’à 512 Kio au moins, jamais coupée (format à vérifier selon la flashcard)">flashcard</a>
                {#if !v.is_active && !v.pinned}
                  <button class="danger" onclick={() => remove(v)}>Supprimer</button>
                {:else}
                  <button
                    class="danger"
                    disabled
                    title={v.is_active ? 'La version active ne peut pas être supprimée : restaure d’abord une autre version.' : 'Désépingle-la d’abord pour pouvoir la supprimer.'}
                  >Supprimer</button>
                {/if}
              </div>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if nextBefore}
    <p><button onclick={more}>Afficher les versions plus anciennes</button></p>
  {/if}

  <h2>Conservation des versions</h2>
  <div class="card">
    <RetentionEditor
      value={game.retention_policy}
      inherit={session.user!.retention_policy}
      onsave={async (p) => {
        game = await api.updateGame(code, { retention_policy: p });
      }}
    />
  </div>
{/if}
