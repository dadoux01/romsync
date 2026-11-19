<script lang="ts">
  import { api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import RetentionEditor from '../components/RetentionEditor.svelte';
  import LanguageSelect from '../components/LanguageSelect.svelte';
  import { t } from '../lib/i18n/index.svelte';

  let current = $state('');
  let next = $state('');
  let confirm = $state('');
  let message = $state('');
  let error = $state('');
  let busy = $state(false);

  async function changePassword(e: SubmitEvent) {
    e.preventDefault();
    message = error = '';
    if (next !== confirm) {
      error = t('common.passwordsDiffer');
      return;
    }
    busy = true;
    try {
      session.user = await api.updateMe({ current_password: current, new_password: next });
      current = next = confirm = '';
      message = t('settings.password.changed');
    } catch (err) {
      error = (err as Error).message;
    } finally {
      busy = false;
    }
  }
</script>

<h1>{t('settings.title')}</h1>

<h2>{t('language.label')}</h2>
<div class="card stack" style="max-width: 420px">
  <LanguageSelect />
  <p class="muted small">{t('language.help')}</p>
</div>

<h2>{t('settings.retention')}</h2>
<div class="card stack">
  <p class="muted small">{t('settings.retention.help')}</p>
  <RetentionEditor
    value={session.user!.retention_policy}
    onsave={async (p) => {
      if (p) session.user = await api.updateMe({ retention_policy: p });
    }}
  />
</div>

<h2>{t('settings.password')}</h2>
<form class="card stack" onsubmit={changePassword} style="max-width: 420px">
  <input type="text" autocomplete="username" value={session.user!.username} hidden readonly />
  <label>{t('settings.password.current')} <input type="password" bind:value={current} autocomplete="current-password" required /></label>
  <label>{t('settings.password.new')} <input type="password" bind:value={next} autocomplete="new-password" required minlength="8" /></label>
  <label>{t('common.confirmation')} <input type="password" bind:value={confirm} autocomplete="new-password" required minlength="8" /></label>
  {#if message}<p class="success">{message}</p>{/if}
  {#if error}<p class="error">{error}</p>{/if}
  <div><button class="primary" disabled={busy}>{t('settings.password.submit')}</button></div>
</form>
