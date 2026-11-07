<script lang="ts">
  import { api } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import RetentionEditor from '../components/RetentionEditor.svelte';

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
      error = 'Les deux mots de passe ne correspondent pas.';
      return;
    }
    busy = true;
    try {
      session.user = await api.updateMe({ current_password: current, new_password: next });
      current = next = confirm = '';
      message = 'Mot de passe changé. Les autres navigateurs ont été déconnectés.';
    } catch (err) {
      error = (err as Error).message;
    } finally {
      busy = false;
    }
  }
</script>

<h1>Réglages</h1>

<h2>Conservation des versions</h2>
<div class="card stack">
  <p class="muted small">Règle par défaut de ton compte ; chaque jeu peut avoir la sienne. Elle est appliquée périodiquement par le serveur.</p>
  <RetentionEditor
    value={session.user!.retention_policy}
    onsave={async (p) => {
      if (p) session.user = await api.updateMe({ retention_policy: p });
    }}
  />
</div>

<h2>Mot de passe</h2>
<form class="card stack" onsubmit={changePassword} style="max-width: 420px">
  <input type="text" autocomplete="username" value={session.user!.username} hidden readonly />
  <label>Mot de passe actuel <input type="password" bind:value={current} autocomplete="current-password" required /></label>
  <label>Nouveau mot de passe <input type="password" bind:value={next} autocomplete="new-password" required minlength="8" /></label>
  <label>Confirmation <input type="password" bind:value={confirm} autocomplete="new-password" required minlength="8" /></label>
  {#if message}<p class="success">{message}</p>{/if}
  {#if error}<p class="error">{error}</p>{/if}
  <div><button class="primary" disabled={busy}>Changer le mot de passe</button></div>
</form>
