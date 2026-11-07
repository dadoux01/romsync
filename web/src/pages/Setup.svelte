<script lang="ts">
  import { api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { navigate } from '../lib/router.svelte';

  let username = $state('');
  let password = $state('');
  let confirm = $state('');
  let error = $state('');
  let busy = $state(false);

  async function submit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    if (password !== confirm) {
      error = 'Les deux mots de passe ne correspondent pas.';
      return;
    }
    busy = true;
    try {
      session.user = await api.setup(username, password);
      session.setupNeeded = false;
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
    <h1>Premier démarrage</h1>
    <p class="muted">Crée le compte administrateur. Les autres comptes seront créés par invitation.</p>
    <label>Identifiant <input bind:value={username} autocomplete="username" required maxlength="32" /></label>
    <label>Mot de passe <input type="password" bind:value={password} autocomplete="new-password" required minlength="8" /></label>
    <label>Confirmation <input type="password" bind:value={confirm} autocomplete="new-password" required minlength="8" /></label>
    {#if error}<p class="error">{error}</p>{/if}
    <button class="primary" disabled={busy}>Créer le compte administrateur</button>
  </form>
</div>
