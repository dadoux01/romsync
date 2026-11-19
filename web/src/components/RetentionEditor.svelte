<script lang="ts">
  import type { RetentionPolicy } from '../lib/api';
  import { describePolicy as describe } from '../lib/format';
  import { t } from '../lib/i18n/index.svelte';

  let {
    value,
    inherit = undefined,
    onsave,
  }: {
    value: RetentionPolicy | null;
    /** The inherited account policy; when set, "inherit" is offered. */
    inherit?: RetentionPolicy;
    onsave: (p: RetentionPolicy | null) => Promise<void>;
  } = $props();

  type Choice = RetentionPolicy['mode'] | 'inherit';
  let mode = $state<Choice>('smart');
  let n = $state(10);
  let busy = $state(false);
  let message = $state('');
  let error = $state('');

  $effect(() => {
    mode = value ? value.mode : 'inherit';
    if (value?.n) n = value.n;
  });

  async function save(e: SubmitEvent) {
    e.preventDefault();
    busy = true;
    message = error = '';
    try {
      const p: RetentionPolicy | null =
        mode === 'inherit' ? null : mode === 'last_n' || mode === 'days' ? { mode, n } : { mode };
      await onsave(p);
      message = t('common.saved');
    } catch (err) {
      error = (err as Error).message;
    } finally {
      busy = false;
    }
  }
</script>

<form class="stack" onsubmit={save}>
  <div class="row">
    <select bind:value={mode} aria-label={t('retention.label')}>
      {#if inherit}<option value="inherit">{t('retention.inherit', { policy: describe(inherit) })}</option>{/if}
      <option value="smart">{t('retention.smart')}</option>
      <option value="all">{t('retention.all')}</option>
      <option value="last_n">{t('retention.lastN')}</option>
      <option value="days">{t('retention.days')}</option>
    </select>
    {#if mode === 'last_n' || mode === 'days'}
      <input type="number" min="1" max="100000" bind:value={n} style="width: 7rem" aria-label={mode === 'days' ? t('retention.daysCount') : t('retention.versionsCount')} />
      <span class="muted">{mode === 'days' ? t('retention.daysUnit') : t('retention.versionsUnit')}</span>
    {/if}
    <button disabled={busy}>{t('common.save')}</button>
  </div>
  {#if mode === 'smart'}
    <p class="muted small">{t('retention.smartHelp')}</p>
  {/if}
  <p class="muted small">{t('retention.kept')}</p>
  {#if message}<p class="success small">{message}</p>{/if}
  {#if error}<p class="error small">{error}</p>{/if}
</form>
