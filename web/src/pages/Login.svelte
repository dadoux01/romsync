<script lang="ts">
  import { api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { t } from '../lib/i18n/index.svelte';
  import LanguageSelect from '../components/LanguageSelect.svelte';

  let username = $state('');
  let password = $state('');
  let error = $state('');
  let busy = $state(false);

  async function submit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    busy = true;
    try {
      session.user = await api.login(username, password);
    } catch (err) {
      error = (err as Error).message;
    } finally {
      busy = false;
    }
  }
</script>

<div class="auth-page">
  <form class="card stack" onsubmit={submit}>
    <div class="brand"><img src="/favicon.svg" alt="" />RomSync</div>
    <h1>{t('login.title')}</h1>
    <label>{t('common.username')} <input bind:value={username} autocomplete="username" required /></label>
    <label>{t('common.password')} <input type="password" bind:value={password} autocomplete="current-password" required /></label>
    {#if error}<p class="error">{error}</p>{/if}
    <button class="primary" disabled={busy}>{t('login.submit')}</button>
    <LanguageSelect compact />
  </form>
</div>
