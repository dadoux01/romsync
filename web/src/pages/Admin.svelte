<script lang="ts">
  import { api, type Invite, type User } from '../lib/api';
  import { session } from '../lib/session.svelte';
  import { formatDate } from '../lib/format';
  import { t } from '../lib/i18n/index.svelte';

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
    const pw = prompt(t('admin.resetPrompt', { name: u.username }));
    if (pw) run(() => api.updateUser(u.id, { password: pw }));
  }

  const STATUS = { pending: 'admin.invite.pending', used: 'admin.invite.used', expired: 'admin.invite.expired' } as const;
</script>

<h1>{t('admin.title')}</h1>
{#if error}<p class="error">{error}</p>{/if}

<h2>{t('admin.invites')}</h2>
<div class="card stack">
  <div class="row">
    <label class="inline">
      {t('admin.validFor')}
      <select bind:value={days}>
        <option value={1}>{t('admin.days1')}</option>
        <option value={7}>{t('admin.days7')}</option>
        <option value={30}>{t('admin.days30')}</option>
      </select>
    </label>
    <button class="primary" onclick={invite}>{t('admin.createInvite')}</button>
  </div>
  {#if link}
    <p class="muted small">{t('admin.linkHelp')}</p>
    <div class="row">
      <input readonly value={link} style="flex: 1; min-width: 16rem" class="mono" onfocus={(e) => e.currentTarget.select()} />
      <button onclick={copy}>{copied ? t('admin.copied') : t('admin.copy')}</button>
    </div>
  {/if}
  {#if invites.length > 0}
    <div class="table-wrap">
      <table class="responsive">
        <thead><tr><th>{t('admin.col.created')}</th><th>{t('admin.col.expires')}</th><th>{t('admin.col.state')}</th></tr></thead>
        <tbody>
          {#each invites as i (i.id)}
            <tr>
              <td>{formatDate(i.created_at)}</td>
              <td>{formatDate(i.expires_at)}</td>
              <td>
                <span class="badge" class:active={i.status === 'pending'}>{t(STATUS[i.status])}</span>
                {#if i.used_by_username}<span class="muted small">{t('admin.invite.usedBy', { name: i.used_by_username })}</span>{/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</div>

<h2>{t('admin.accounts')}</h2>
<div class="card table-wrap">
  <table class="responsive">
    <thead><tr><th>{t('common.username')}</th><th>{t('admin.col.role')}</th><th>{t('admin.col.accountCreated')}</th><th></th></tr></thead>
    <tbody>
      {#each users as u (u.id)}
        <tr>
          <td>
            <strong>{u.username}</strong>
            {#if u.disabled_at}<span class="badge danger">{t('admin.disabled')}</span>{/if}
          </td>
          <td>{u.role === 'admin' ? t('admin.role.admin') : t('admin.role.user')}</td>
          <td>{formatDate(u.created_at)}</td>
          <td>
            <div class="row">
              <button onclick={() => resetPassword(u)}>{t('admin.resetPassword')}</button>
              {#if u.id !== session.user!.id}
                {#if u.disabled_at}
                  <button onclick={() => run(() => api.updateUser(u.id, { disabled: false }))}>{t('admin.enable')}</button>
                {:else}
                  <button class="danger" onclick={() => run(() => api.updateUser(u.id, { disabled: true }))}>{t('admin.disable')}</button>
                {/if}
              {/if}
            </div>
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>
<p class="muted small">{t('admin.privacy')}</p>
