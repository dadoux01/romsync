<script lang="ts">
  import { LANGUAGE_NAMES, languageChoice, setLanguage, t, type LanguageChoice } from '../lib/i18n/index.svelte';

  let { compact = false }: { compact?: boolean } = $props();
</script>

<label class:inline={compact}>
  {t('language.label')}
  <select value={languageChoice()} onchange={(e) => setLanguage(e.currentTarget.value as LanguageChoice)}>
    <option value="system">{t('language.system')}</option>
    {#each Object.entries(LANGUAGE_NAMES) as [code, name] (code)}
      <option value={code} lang={code}>{name}</option>
    {/each}
  </select>
</label>
