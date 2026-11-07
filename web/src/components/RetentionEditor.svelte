<script lang="ts">
  import type { RetentionPolicy } from '../lib/api';
  import { describePolicy as describe } from '../lib/format';

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
      message = 'Enregistré.';
    } catch (err) {
      error = (err as Error).message;
    } finally {
      busy = false;
    }
  }
</script>

<form class="stack" onsubmit={save}>
  <div class="row">
    <select bind:value={mode} aria-label="Mode de conservation">
      {#if inherit}<option value="inherit">Comme le compte ({describe(inherit)})</option>{/if}
      <option value="smart">Intelligente</option>
      <option value="all">Tout garder</option>
      <option value="last_n">Les N dernières versions</option>
      <option value="days">Les versions de moins de N jours</option>
    </select>
    {#if mode === 'last_n' || mode === 'days'}
      <input type="number" min="1" max="100000" bind:value={n} style="width: 7rem" aria-label={mode === 'days' ? 'Nombre de jours' : 'Nombre de versions'} />
      <span class="muted">{mode === 'days' ? 'jours' : 'versions'}</span>
    {/if}
    <button disabled={busy}>Enregistrer</button>
  </div>
  {#if mode === 'smart'}
    <p class="muted small">Tout sur 7 jours, puis la plus récente de chaque jour jusqu’à 30 jours, puis une par semaine.</p>
  {/if}
  <p class="muted small">La version active et les versions épinglées ne sont jamais supprimées.</p>
  {#if message}<p class="success small">{message}</p>{/if}
  {#if error}<p class="error small">{error}</p>{/if}
</form>
