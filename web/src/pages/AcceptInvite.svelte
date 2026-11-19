<script lang="ts">
  import { api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { navigate } from '../lib/router.svelte';
  import { t } from '../lib/i18n/index.svelte';
  import LanguageSelect from '../components/LanguageSelect.svelte';

  let { token }: { token: string } = $props();
  let username = $state('');
  let password = $state('');
  let confirm = $state('');
  let error = $state('');
  let busy = $state(false);

  async function submit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    if (password !== confirm) {
      error = t('common.passwordsDiffer');
      return;
    }
    busy = true;
    try {
      session.user = await api.acceptInvite(token, username, password);
      navigate('/', true);
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
    <h1>{t('invite.title')}</h1>
    {#if session.user}
      <p class="notice">{t('invite.loggedIn', { name: session.user.username })}</p>
    {/if}
    <label>{t('common.username')} <input bind:value={username} autocomplete="username" required maxlength="32" /></label>
    <label>{t('common.password')} <input type="password" bind:value={password} autocomplete="new-password" required minlength="8" /></label>
    <label>{t('common.confirmation')} <input type="password" bind:value={confirm} autocomplete="new-password" required minlength="8" /></label>
    {#if error}<p class="error">{error}</p>{/if}
    <button class="primary" disabled={busy}>{t('invite.submit')}</button>
    <LanguageSelect compact />
  </form>
</div>
