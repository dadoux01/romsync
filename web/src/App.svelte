<script lang="ts">
  import { onMount } from 'svelte';
  import { route, match, navigate } from './lib/router.svelte';
  import { session, loadSession } from './lib/session.svelte';
  import { api } from './lib/api';
  import Setup from './pages/Setup.svelte';
  import Login from './pages/Login.svelte';
  import AcceptInvite from './pages/AcceptInvite.svelte';
  import Games from './pages/Games.svelte';
  import Game from './pages/Game.svelte';
  import Import from './pages/Import.svelte';
  import Devices from './pages/Devices.svelte';
  import Settings from './pages/Settings.svelte';
  import Admin from './pages/Admin.svelte';
  import NotFound from './pages/NotFound.svelte';

  onMount(loadSession);

  const invite = $derived(match('/invite/:token', route.path));
  const game = $derived(match('/games/:code', route.path));
  const path = $derived(route.path.replace(/\/+$/, '') || '/');

  const nav = [
    { href: '/', label: 'Jeux' },
    { href: '/import', label: 'Importer' },
    { href: '/devices', label: 'Appareils' },
    { href: '/settings', label: 'Réglages' },
  ];

  function isCurrent(href: string) {
    return href === '/' ? path === '/' || path.startsWith('/games') : path.startsWith(href);
  }

  async function logout() {
    try {
      await api.logout();
    } finally {
      session.user = null;
      navigate('/', true);
    }
  }
</script>

{#if !session.ready}
  <div class="auth-page"><p class="muted">Chargement…</p></div>
{:else if session.setupNeeded}
  <Setup />
{:else if invite}
  <AcceptInvite token={invite.token} />
{:else if !session.user}
  <Login />
{:else}
  <header>
    <div class="inner">
      <a class="brand" href="/"><img src="/favicon.svg" alt="" />RomSync</a>
      <nav>
        {#each nav as item (item.href)}
          <a href={item.href} aria-current={isCurrent(item.href) ? 'page' : undefined}>{item.label}</a>
        {/each}
        {#if session.user.role === 'admin'}
          <a href="/admin" aria-current={isCurrent('/admin') ? 'page' : undefined}>Administration</a>
        {/if}
      </nav>
      <div class="row user">
        <span class="muted small">{session.user.username}</span>
        <button class="link small" onclick={logout}>Se déconnecter</button>
      </div>
    </div>
  </header>
  <main>
    {#if path === '/'}
      <Games />
    {:else if game}
      {#key game.code}<Game code={game.code} />{/key}
    {:else if path === '/import'}
      <Import />
    {:else if path === '/devices'}
      <Devices />
    {:else if path === '/settings'}
      <Settings />
    {:else if path === '/admin' && session.user.role === 'admin'}
      <Admin />
    {:else}
      <NotFound />
    {/if}
  </main>
{/if}

<style>
  header {
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    position: sticky;
    top: 0;
    z-index: 1;
  }
  .inner {
    max-width: 1000px;
    margin: 0 auto;
    padding: 0.6rem 1rem;
    display: flex;
    align-items: center;
    gap: 1.25rem;
    flex-wrap: wrap;
  }
  .brand {
    color: inherit;
    text-decoration: none;
  }
  nav {
    display: flex;
    gap: 0.25rem;
    flex: 1;
    flex-wrap: wrap;
  }
  nav a {
    color: var(--muted);
    text-decoration: none;
    padding: 0.35rem 0.7rem;
    border-radius: 8px;
    font-weight: 500;
  }
  nav a:hover {
    color: var(--text);
  }
  nav a[aria-current='page'] {
    background: var(--surface-2);
    color: var(--text);
  }
  main {
    max-width: 1000px;
    margin: 0 auto;
    padding: 1.5rem 1rem 3rem;
  }
</style>
