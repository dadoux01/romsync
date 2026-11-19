<script lang="ts">
  import { api, type Game, type Version } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { describeSizeEvent, formatDate, formatSize, relativeDate, shortHash } from '../lib/format';
  import { regionName } from '../lib/saves';
  import { t } from '../lib/i18n/index.svelte';
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
        error = t('game.notFound');
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
    if (!confirm(t('game.confirmRestore', { date: formatDate(v.saved_at) }))) return;
    run(() => api.activate(v.id));
  }

  function remove(v: Version) {
    if (!confirm(t('game.confirmDelete', { date: formatDate(v.saved_at) }))) return;
    run(() => api.deleteVersion(v.id));
  }

  function editNote(v: Version) {
    const note = prompt(t('game.notePrompt'), v.note);
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
    if (v.base_version_id === null) return t('game.base.none');
    const base = versions.find((x) => x.id === v.base_version_id);
    if (!base) return t('game.base.missing', { id: v.base_version_id });
    return t('game.base.from', { date: formatDate(base.saved_at), device: base.device_name ?? t('common.website') });
  }

  // "Conflict resolved automatically": the latest upload diverged. The other
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
  <p><a href="/">{t('game.backToList')}</a></p>
{:else if !game}
  <p class="muted">{t('common.loading')}</p>
{:else}
  <p class="small"><a href="/">{t('game.back')}</a></p>
  <div class="spread">
    {#if editingTitle}
      <form class="row" onsubmit={saveTitle}>
        <input bind:value={title} maxlength="128" required aria-label={t('game.titleLabel')} />
        <button class="primary">{t('game.rename')}</button>
        <button type="button" onclick={() => (editingTitle = false)}>{t('common.cancel')}</button>
      </form>
    {:else}
      <h1>
        {game.title}
        <button class="link small" onclick={() => ((title = game!.title), (editingTitle = true))}>{t('game.renameLink')}</button>
      </h1>
    {/if}
    <a class="button primary" href={`/import?game=${encodeURIComponent(code)}`}>{t('games.import')}</a>
  </div>
  <p class="muted">
    <span class="mono">{game.code}</span>
    {#if game.region}· {regionName(game.region) ?? t('game.region', { region: game.region })}{/if}
    · {t('game.summary', { size: formatSize(game.chip_size), seen: relativeDate(game.first_seen_at) })}
  </p>

  {#if actionError}<p class="error">{actionError}</p>{/if}

  {#if conflict}
    <div class="notice stack">
      <strong>{t('game.conflict.title')}</strong>
      <span>
        {conflict.latest.device_name
          ? t('game.conflict.byDevice', { date: formatDate(conflict.latest.uploaded_at), device: conflict.latest.device_name })
          : t('game.conflict.fromSite', { date: formatDate(conflict.latest.uploaded_at) })}
        {conflict.latest.is_active ? t('game.conflict.isActive') : t('game.conflict.notActive')}
      </span>
      {#if conflict.other && !conflict.other.is_active}
        <div><button onclick={() => activate(conflict.other!)}>{t('game.conflict.activateOther', { date: formatDate(conflict.other.saved_at) })}</button></div>
      {/if}
    </div>
  {/if}

  <h2>{t('game.history')}</h2>
  <div class="card table-wrap">
    <table class="responsive">
      <thead>
        <tr><th>{t('game.col.savedAt')}</th><th>{t('game.col.origin')}</th><th>{t('game.col.size')}</th><th>{t('game.col.state')}</th><th></th></tr>
      </thead>
      <tbody>
        {#each versions as v (v.id)}
          <tr>
            <td>
              {formatDate(v.saved_at)}
              {#if v.saved_at_reported}
                <span class="badge warn" title={t('game.clockFixed.title', { date: formatDate(v.saved_at_reported) })}>{t('game.clockFixed')}</span>
              {/if}
              {#if v.note}<div class="muted small">{v.note}</div>{/if}
            </td>
            <td>
              {v.device_name ?? t('common.website')}
              {#if v.emulator}<div class="muted small">{v.emulator}</div>{/if}
            </td>
            <td>
              {formatSize(v.size)}
              {#if v.size_event}
                <span class="badge warn" title={describeSizeEvent(v.size_event, v.size)}>
                  {v.size_event.type === 'trimmed' ? t('game.size.trimmed') : v.size_event.type === 'shrunk' ? t('game.size.shrunk') : t('game.size.forced')}
                </span>
                <div class="muted small">{describeSizeEvent(v.size_event, v.size)}</div>
              {/if}
              <div class="muted small mono" title={v.sha256}>{shortHash(v.sha256)}</div>
            </td>
            <td>
              <div class="row">
                {#if v.is_active}<span class="badge active">{t('game.badge.active')}</span>{/if}
                {#if v.conflict}<span class="badge warn" title={t('game.badge.divergent.title')}>{t('game.badge.divergent')}</span>{/if}
                {#if v.pinned}<span class="badge">{t('game.badge.pinned')}</span>{/if}
              </div>
              {#if v.conflict}<div class="muted small">{baseLabel(v)}</div>{/if}
            </td>
            <td>
              <div class="row">
                {#if !v.is_active}<button onclick={() => activate(v)}>{t('game.restore')}</button>{/if}
                <button onclick={() => run(() => api.updateVersion(v.id, { pinned: !v.pinned }))}>
                  {v.pinned ? t('game.unpin') : t('game.pin')}
                </button>
                <button onclick={() => editNote(v)}>{t('game.note')}</button>
                <a class="button" href={api.exportURL(v.id, 'raw')} download>.sav</a>
                <a class="button" href={api.exportURL(v.id, 'desmume')} download>.dsv</a>
                <a class="button" href={api.exportURL(v.id, 'flashcard')} download title={t('game.flashcard.title')}>{t('game.flashcard')}</a>
                {#if !v.is_active && !v.pinned}
                  <button class="danger" onclick={() => remove(v)}>{t('game.delete')}</button>
                {:else}
                  <button
                    class="danger"
                    disabled
                    title={v.is_active ? t('game.delete.active') : t('game.delete.pinned')}
                  >{t('game.delete')}</button>
                {/if}
              </div>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
  {#if nextBefore}
    <p><button onclick={more}>{t('game.more')}</button></p>
  {/if}

  <h2>{t('settings.retention')}</h2>
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
