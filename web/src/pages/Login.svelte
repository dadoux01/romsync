<script lang="ts">
  import { api } from '../lib/api';
  import { session } from '../lib/session.svelte';

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
    <h1>Connexion</h1>
    <label>Identifiant <input bind:value={username} autocomplete="username" required /></label>
    <label>Mot de passe <input type="password" bind:value={password} autocomplete="current-password" required /></label>
    {#if error}<p class="error">{error}</p>{/if}
    <button class="primary" disabled={busy}>Se connecter</button>
  </form>
</div>
