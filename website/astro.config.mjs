// @ts-check
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://apropos.zawalid.com',
  output: 'static',
  build: { inlineStylesheets: 'always' },
});
