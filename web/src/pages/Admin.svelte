<script lang="ts">
  import { api, type Invite, type User } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { formatDate } from '../lib/format';

  let users = $state<User[]>([]);
  let invites = $state<Invite[]>([]);
  let days = $state(7);
  let link = $state('');
  let copied = $state(false);
  let error = $state('');

  async function load() {
    try {
      [users, invites] = await Promise.all([api.users(), api.invites()]);
    } catch (err) {
      error = (err as Error).message;
    }
  }
  $effect(() => {
    load();
  });

  async function run(fn: () => Promise<unknown>) {
    error = '';
    try {
      await fn();
      await load();
    } catch (err) {
      error = (err as Error).message;
    }
  }

  async function invite() {
    await run(async () => {
      const res = await api.createInvite(days);
      link = `${location.origin}/invite/${res.token}`;
      copied = false;
    });
  }

  async function copy(e: Event) {
    try {
      await navigator.clipboard.writeText(link);
      copied = true;
    } catch {
      // The clipboard API needs HTTPS: select the text instead.
      ((e.currentTarget as HTMLElement).previousElementSibling as HTMLInputElement)?.select();
    }
  }

  function resetPassword(u: User) {
    const pw = prompt(`Nouveau mot de passe pour ${u.username} (8 caractères minimum) :`);
    if (pw) run(() => api.updateUser(u.id, { password: pw }));
  }

  const STATUS = { pending: 'en attente', used: 'utilisée', expired: 'expirée' } as const;
</script>

<h1>Administration</h1>
{#if error}<p class="error">{error}</p>{/if}

<h2>Invitations</h2>
<div class="card stack">
  <div class="row">
    <label class="inline">
      Valable
      <select bind:value={days}>
        <option value={1}>1 jour</option>
        <option value={7}>7 jours</option>
        <option value={30}>30 jours</option>
      </select>
    </label>
    <button class="primary" onclick={invite}>Créer un lien d’invitation</button>
  </div>
  {#if link}
    <p class="muted small">Lien à usage unique, affiché une seule fois : envoie-le à la personne invitée.</p>
    <div class="row">
      <input readonly value={link} style="flex: 1; min-width: 16rem" class="mono" onfocus={(e) => e.currentTarget.select()} />
      <button onclick={copy}>{copied ? 'Copié' : 'Copier'}</button>
    </div>
  {/if}
  {#if invites.length > 0}
    <div class="table-wrap">
      <table class="responsive">
        <thead><tr><th>Créée le</th><th>Expire le</th><th>État</th></tr></thead>
        <tbody>
          {#each invites as i (i.id)}
            <tr>
              <td>{formatDate(i.created_at)}</td>
              <td>{formatDate(i.expires_at)}</td>
              <td>
                <span class="badge" class:active={i.status === 'pending'}>{STATUS[i.status]}</span>
                {#if i.used_by_username}<span class="muted small">par {i.used_by_username}</span>{/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</div>

<h2>Comptes</h2>
<div class="card table-wrap">
  <table class="responsive">
    <thead><tr><th>Identifiant</th><th>Rôle</th><th>Créé le</th><th></th></tr></thead>
    <tbody>
      {#each users as u (u.id)}
        <tr>
          <td>
            <strong>{u.username}</strong>
            {#if u.disabled_at}<span class="badge danger">désactivé</span>{/if}
          </td>
          <td>{u.role === 'admin' ? 'administrateur' : 'utilisateur'}</td>
          <td>{formatDate(u.created_at)}</td>
          <td>
            <div class="row">
              <button onclick={() => resetPassword(u)}>Réinitialiser le mot de passe</button>
              {#if u.id !== session.user!.id}
                {#if u.disabled_at}
                  <button onclick={() => run(() => api.updateUser(u.id, { disabled: false }))}>Réactiver</button>
                {:else}
                  <button class="danger" onclick={() => run(() => api.updateUser(u.id, { disabled: true }))}>Désactiver</button>
                {/if}
              {/if}
            </div>
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>
<p class="muted small">L’administration ne donne pas accès aux saves des autres comptes.</p>
