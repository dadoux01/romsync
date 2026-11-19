<script lang="ts">
  import { api, ApiError, type Game, type Profile, type UploadResult } from '../lib/api';
  import { route } from '../lib/router.svelte';
  import { describeSizeEvent, formatDate, formatSize } from '../lib/format';
  import {
    SYSTEMS,
    hasMgbaClock,
    isValidGameCode,
    parseRomHeader,
    romTitleGb,
    profileFor,
    rawSize,
    systemOf,
    systemOfRomName,
    withSystem,
    type GameSystem,
  } from '../lib/saves';
  import { randomId } from '../lib/sha256';
  import { sha1Pure } from '../lib/sha1';
  import { t } from '../lib/i18n/index.svelte';

  let games = $state<Game[]>([]);
  let file = $state<File | null>(null);
  let data = $state<Uint8Array | null>(null);
  let target = $state(new URLSearchParams(route.search).get('game') ?? '');
  let newSystem = $state<GameSystem>('nds');
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
  const code = $derived(
    isNew ? withSystem(newSystem, newCode.includes(':') ? newCode.trim() : newCode.trim().toUpperCase()) : target,
  );
  const selected = $derived(games.find((g) => g.code === code));
  // The server removes the DeSmuME footer (DS) or mGBA's cartridge clock (GBA).
  const profile = $derived<Profile>(data ? profileFor(systemOf(code), data) : 'raw');

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
    savedAt = toLocalInput(new Date(f.lastModified));
  }

  async function pickRom(e: Event) {
    const f = (e.currentTarget as HTMLInputElement).files?.[0];
    if (!f) return;
    // Read locally: the ROM never leaves the browser. Without a game code
    // (Game Boy, homebrew), the identifier is the SHA-1 of the whole ROM.
    let header = parseRomHeader(new Uint8Array(await f.slice(0, 512).arrayBuffer()), f.name);
    const system = header?.system ?? systemOfRomName(f.name);
    if (!header && system) {
      const title = system === 'gb' ? romTitleGb(new Uint8Array(await f.slice(0, 0x150).arrayBuffer())) : '';
      header = { system, code: `h:${sha1Pure(new Uint8Array(await f.arrayBuffer()))}`, title };
    }
    if (!header) {
      error = t('import.romNoCode');
      return;
    }
    error = '';
    const existing = games.find((g) => g.code === withSystem(header.system, header.code));
    if (existing) {
      target = existing.code;
    } else {
      target = '__new__';
      newSystem = header.system;
      newCode = header.code;
      newTitle = header.title;
    }
  }

  async function submit(e: SubmitEvent, force = false) {
    e?.preventDefault();
    if (!data || !file) return;
    if (!isValidGameCode(code)) {
      error = t('import.invalidCode');
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

<h1>{t('import.title')}</h1>
<p class="muted">{@html t('import.intro.html')}</p>

{#if result}
  <div class="card stack">
    {#if result.created}
      <p class="success">{result.active ? t('import.doneActive') : t('import.done')}</p>
      {#if result.conflict}<p class="muted small">{t('import.divergent')}</p>{/if}
      {#if result.version.size_event}<p class="muted small">{describeSizeEvent(result.version.size_event, result.version.size)}</p>{/if}
    {:else}
      <p>{t('import.identical')}</p>
    {/if}
    <div class="row">
      <a class="button primary" href={`/games/${encodeURIComponent(result.version.game_code)}`}>{t('import.viewGame')}</a>
      <button onclick={() => ((result = null), (file = null), (data = null))}>{t('import.another')}</button>
    </div>
  </div>
{:else}
  <form class="card stack" onsubmit={(e) => submit(e)}>
    <label>
      {t('import.file')}
      <input type="file" accept=".sav,.dsv,.srm,application/octet-stream" onchange={pickSave} required />
    </label>
    {#if data}
      <p class="muted small">
        {t('import.detected')}
        <strong
          >{profile === 'desmume'
            ? t('import.format.desmume')
            : profile === 'mgba' || profile === 'mgba-gb'
              ? hasMgbaClock(data, profile)
                ? t('import.format.mgbaClock')
                : t('import.format.mgba')
              : t('import.format.raw')}</strong
        > ·
        {t('import.saveOf', { size: formatSize(rawSize(data, profile)) })}
      </p>

      <label>
        {t('import.game')}
        <select bind:value={target}>
          {#if games.length > 0}<option value="" disabled>{t('import.chooseGame')}</option>{/if}
          {#each games as g (g.code)}
            <option value={g.code}>{g.title} ({g.code})</option>
          {/each}
          <option value="__new__">{t('import.newGame')}</option>
        </select>
      </label>

      {#if isNew}
        <div class="row">
          <label>
            {t('system.label')}
            <select bind:value={newSystem}>
              {#each SYSTEMS as s (s)}<option value={s}>{t(`system.${s}`)}</option>{/each}
            </select>
          </label>
          <label>{t('import.code')} <input bind:value={newCode} placeholder="IRBF" required class="mono" /></label>
          <label style="flex: 1">{t('import.titleLabel')} <input bind:value={newTitle} placeholder={t('import.titlePlaceholder')} maxlength="128" /></label>
        </div>
      {/if}
      <label>
        <span>{t('import.rom')} <span class="muted small">{t('import.romHelp')}</span></span>
        <input type="file" accept=".nds,.dsi,.srl,.gba,.gb,.gbc,.sgb" onchange={pickRom} />
      </label>

      <label>
        {t('import.date')}
        <input type="datetime-local" bind:value={savedAt} required />
      </label>
      {#if selected?.active_version}
        <p class="muted small">{t('import.currentActive', { date: formatDate(selected.active_version.saved_at) })}</p>
      {/if}
      <label class="inline"><input type="checkbox" bind:checked={makeActive} /> {t('import.makeActive')}</label>

      {#if error}<p class="error">{error}</p>{/if}
      {#if sizeMismatch}
        <p class="notice">{t('import.sizeMismatch', { size: formatSize(selected?.chip_size) })}</p>
        <div><button type="button" class="danger" disabled={busy} onclick={(e) => submit(e as unknown as SubmitEvent, true)}>{t('import.force')}</button></div>
      {/if}
      <div><button class="primary" disabled={busy || !code}>{t('import.submit')}</button></div>
    {/if}
  </form>
{/if}
