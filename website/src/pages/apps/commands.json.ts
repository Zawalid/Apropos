import type { APIRoute } from 'astro';
import { measurement } from '../../data/apps';

/** Every measured command as [app, menu path, title, shortcut], fetched by the search on /apps/ when it is used. */
export const GET: APIRoute = () => {
  const rows = (measurement?.apps ?? []).flatMap((app) =>
    app.commands.map((c) => [app.name, c.path.join(' › '), c.title, c.shortcut ?? '']),
  );
  return new Response(JSON.stringify(rows), { headers: { 'Content-Type': 'application/json; charset=utf-8' } });
};
