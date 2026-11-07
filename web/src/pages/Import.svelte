<script lang="ts">
  import { api, ApiError, type Game, type Profile, type UploadResult } from '../lib/api';
  import { route } from '../lib/router.svelte';
  import { formatDate, formatSize } from '../lib/format';
  import { isDeSmuME, isValidGameCode, parseRomHeader, rawSize } from '../lib/saves';
  import { randomId } from '../lib/sha256';

  let games = $state<Game[]>([]);
  let file = $state<File | null>(null);
  let data = $state<Uint8Array | null>(null);
  let profile = $state<Profile>('raw');
  let target = $state(new URLSearchParams(route.search).get('game') ?? '');
  let newCode = $state('');
  let newTitle = $state('');
  let savedAt = $state('');
  let makeActive = $state(true);
  let busy = $state(false);
  let error = $state('');
  let sizeMismatch = $state(false);
  let result = $state<UploadResult | null>(null);
  let uploadId = randomId();

  const isNew = $derived(target === '__new__' || (games.length === 0 && target === ''));
  // Cartridge codes are upper case; x: and h: identifiers are lower case.
  const code = $derived(isNew ? (newCode.includes(':') ? newCode.trim() : newCode.trim().toUpperCase()) : target);
  const selected = $derived(games.find((g) => g.code === code));

  $effect(() => {
    api.games().then((g) => {
      games = g;
      if (target && target !== '__new__' && !g.some((x) => x.code === target)) target = '';
    });
  });

  function toLocalInput(d: Date) {
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  async function pickSave(e: Event) {
    const f = (e.currentTarget as HTMLInputElement).files?.[0];
    result = null;
    error = '';
    sizeMismatch = false;
    uploadId = randomId();
    if (!f) return;
    file = f;
    data = new Uint8Array(await f.arrayBuffer());
    profile = isDeSmuME(data) ? 'desmume' : 'raw';
    savedAt = toLocalInput(new Date(f.lastModified));
  }

  async function pickRom(e: Event) {
    const f = (e.currentTarget as HTMLInputElement).files?.[0];
    if (!f) return;
    // Only the header is read, locally: the ROM never leaves the browser.
    const header = parseRomHeader(new Uint8Array(await f.slice(0, 512).arrayBuffer()));
    if (!header) {
      error = 'Cette ROM n’a pas de code de jeu valide (homebrew ?) : saisis un identifiant x:nom.';
      return;
    }
    error = '';
    const existing = games.find((g) => g.code === header.code);
    if (existing) {
      target = existing.code;
    } else {
      target = '__new__';
      newCode = header.code;
      newTitle = header.title;
    }
  }

  async function submit(e: SubmitEvent, force = false) {
    e?.preventDefault();
    if (!data || !file) return;
    if (!isValidGameCode(code)) {
      error = 'Identifiant de jeu invalide : 4 caractères (ex. IRBF), h:<sha1> ou x:nom-en-minuscules.';
      return;
    }
    busy = true;
    error = '';
    try {
      result = await api.upload({
        code,
        file: data,
        profile,
        savedAt: new Date(savedAt),
        baseVersionId: selected?.active_version?.id ?? null,
        title: isNew ? newTitle.trim() || undefined : undefined,
        forceSize: force,
        uploadId,
      });
      sizeMismatch = false;
      if (makeActive && result.created && !result.active) {
        result = { ...result, version: await api.activate(result.version.id), active: true };
      }
    } catch (err) {
      sizeMismatch = err instanceof ApiError && err.code === 'size_mismatch';
      error = (err as Error).message;
    } finally {
      busy = false;
    }
  }
</script>

<h1>Importer une save</h1>
<p class="muted">
  Pour une DS avec flashcard (DSTT, R4…) ou en dépannage : envoie un fichier <code>.sav</code> (brut) ou <code>.dsv</code>
  (DeSmuME). Pour récupérer une save dans un format donné, ouvre le jeu et télécharge la version voulue.
</p>

{#if result}
  <div class="card stack">
    {#if result.created}
      <p class="success">Version importée{result.active ? ' et active' : ''}.</p>
      {#if result.conflict}<p class="muted small">Elle ne partait pas de la version active : elle est marquée divergente.</p>{/if}
    {:else}
      <p>Cette save est identique à la version active : rien n’a été créé.</p>
    {/if}
    <div class="row">
      <a class="button primary" href={`/games/${encodeURIComponent(result.version.game_code)}`}>Voir le jeu</a>
      <button onclick={() => ((result = null), (file = null), (data = null))}>Importer une autre save</button>
    </div>
  </div>
{:else}
  <form class="card stack" onsubmit={(e) => submit(e)}>
    <label>
      Fichier de save
      <input type="file" accept=".sav,.dsv,.srm,application/octet-stream" onchange={pickSave} required />
    </label>
    {#if data}
      <p class="muted small">
        Format détecté : <strong>{profile === 'desmume' ? 'DeSmuME (.dsv)' : 'brut (.sav)'}</strong> · save de
        {formatSize(rawSize(data, profile))}
      </p>

      <label>
        Jeu
        <select bind:value={target}>
          {#if games.length > 0}<option value="" disabled>Choisir un jeu…</option>{/if}
          {#each games as g (g.code)}
            <option value={g.code}>{g.title} ({g.code})</option>
          {/each}
          <option value="__new__">Nouveau jeu…</option>
        </select>
      </label>

      {#if isNew}
        <div class="row">
          <label>Identifiant <input bind:value={newCode} placeholder="IRBF" required class="mono" /></label>
          <label style="flex: 1">Titre <input bind:value={newTitle} placeholder="Pokémon Noire" maxlength="128" /></label>
        </div>
      {/if}
      <label>
        <span>Ou désigne la ROM <span class="muted small">(seul l’en-tête est lu, dans le navigateur ; rien n’est envoyé)</span></span>
        <input type="file" accept=".nds,.dsi,.srl" onchange={pickRom} />
      </label>

      <label>
        Date de la save
        <input type="datetime-local" bind:value={savedAt} required />
      </label>
      {#if selected?.active_version}
        <p class="muted small">Version active actuelle : {formatDate(selected.active_version.saved_at)}.</p>
      {/if}
      <label class="inline"><input type="checkbox" bind:checked={makeActive} /> Rendre cette version active même si elle est plus ancienne</label>

      {#if error}<p class="error">{error}</p>{/if}
      {#if sizeMismatch}
        <p class="notice">
          La taille ne correspond pas à celle des saves déjà connues pour ce jeu
          ({formatSize(selected?.chip_size)}). Vérifie que c’est le bon jeu avant de forcer.
        </p>
        <div><button type="button" class="danger" disabled={busy} onclick={(e) => submit(e as unknown as SubmitEvent, true)}>Forcer la nouvelle taille</button></div>
      {/if}
      <div><button class="primary" disabled={busy || !code}>Importer</button></div>
    {/if}
  </form>
{/if}
