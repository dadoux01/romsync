<script lang="ts">
  // Shown for unknown client-side routes.
  import { t } from '../lib/i18n/index.svelte';
</script>

<h1>{t('notFound.title')}</h1>
<p><a href="/">{t('notFound.back')}</a></p>
